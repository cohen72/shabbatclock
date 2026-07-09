# User Communication for ShabbatClock — Design

**Date:** 2026-07-07
**Status:** Approved design, pending spec review
**Primary consumer:** ShabbatClock (first app to adopt these modules)
**Shared surface:** DeliciousKit (Swift client) + a new shared Delicious backend (Cloud Function + Loops.so)

## Problem

ShabbatClock has no way to reach its users. There is no mailing list, no "what's
new" surface, and no review/feedback prompt. Apple never exposes a subscriber's
email to the developer, so the only way to build a list of real customers — and to
give paying subscribers "more attention and content" — is an in-app opt-in.

Verified context (App Store Connect API, 2026-07):
- ShabbatClock has **1 active paying weekly subscriber** (US, $0.99/wk → $0.70
  proceeds) and **1 active free trial** (DE). Subscriptions are real and renewing.
- The app already has StoreKit 2 premium (`StoreManager.isPremium`), Firebase
  Analytics + Mixpanel dual-write, and Firebase Remote Config. It does **not**
  depend on DeliciousKit at all today; its onboarding/paywall are bespoke.

## Scope

Three features, split by where they live and how much infrastructure they need:

1. **What's New** — per-version release-notes sheet, shown once per version. Client-only.
2. **Review prompts** — gated `SKStoreReviewController` request after a positive moment. Client-only.
3. **Newsletter signup** — optional Sign in with Apple → email capture → transparent
   marketing opt-in → stored in a shared backend and pushed to Loops.so. Needs backend.

Out of scope (explicitly deferred):
- Ripping out ShabbatClock's bespoke onboarding/paywall to rebuild on DeliciousKit
  primitives. Keep the bespoke flows; only bolt on leaf modules.
- Extracting ShabbatClock's permission-UX into a reusable DeliciousKit step type.
  This is happening in a **separate concurrent session** that refactors DeliciousKit's
  onboarding to absorb ShabbatClock's permission + optional-paywall patterns.
- App Store Server Notifications webhook to keep premium status live server-side
  (future phase; v1 snapshots `isPremium` at signup time).
- Syncing Loops unsubscribes back into Firestore (v2 webhook).

## Dependency on the concurrent DeliciousKit refactor

A separate session is reshaping DeliciousKit's onboarding/step/paywall API. To avoid
building against a moving target, work is split:

**Safe to build now (no DeliciousKit contact):**
- The shared newsletter **backend** (Cloud Function + Firestore + Loops).
- This design doc.

**Hold until the refactor lands:**
- DeliciousKit `Newsletter.swift` Swift client + Auth adapter wiring.
- ShabbatClock's onboarding integration (ideally becomes "declare a newsletter step
  in config" once the refactor produces reusable permission/paywall steps).

## Architecture

### Feature 1 — What's New (client-only)

Adopt DeliciousKit's existing `WhatsNewView` / `WhatsNewConfig` / `WhatsNewItem`
(already built: per-version "seen" tracking via `UserDefaults` key
`launchkit.lastSeenWhatsNew`). ShabbatClock defines a `WhatsNewConfig` in code per
release. Shown once on first launch after the app version changes.

- **Trigger:** on app foreground/launch, if `WhatsNewConfig.version` != last seen.
- **Content:** defined in code (systemImage + title + description per item), localized
  EN/HE like all ShabbatClock strings.
- **No backend.** Ships in the same release as the client integration.

### Feature 2 — Review prompts (client-only)

Adopt DeliciousKit's `ReviewPrompter` (already built: `minSessions=3`,
`maxPromptsPerYear=3`, per-version cap, only fires after a recorded positive event).

- **Positive-event trigger:** an alarm **fires and auto-stops successfully on its
  own** — i.e. the full cycle (scheduled → rang → cleanly silenced) completed with
  no user intervention. This is the app's actual core promise (auto-shut-off), so
  it's a genuine "it worked" signal — unlike a manual stop-button tap, which this
  app deliberately has almost no path to, or raw session count, which says nothing
  about whether an alarm ever fired correctly.
  Wire `recordPositiveEvent()` at the existing auto-stop completion points in
  `AlarmKitService` (in-process auto-stop firing, silencer alarm firing, or
  composed-sound tail completing — whichever path the alarm took), then call
  `promptIfAppropriate(in: scene)` on next foreground.
- **No backend.**

### Feature 3 — Newsletter signup (needs shared backend)

**Client (deferred to post-refactor):**
- Surfaces in two places: (a) an onboarding step ("Stay in the loop") after the
  existing permission pages, and (b) a Settings row ("Get updates by email") for
  users who skip onboarding or installed before this version.
- Copy is explicit and honest: "Get product updates and occasional offers by email.
  Unsubscribe anytime." Localized EN/HE. A "Not Now" skip mirrors the existing
  permission-page pattern.
- Flow: tap → Sign in with Apple (`ASAuthorizationController` via DeliciousKit
  `AuthProvider` Apple adapter) → obtain email (Apple private-relay address is fine)
  → POST to the shared backend endpoint → on success, persist a local `@AppStorage`
  flag so we never re-prompt. Failure keeps the Settings row available to retry.
- **Capture-only:** no account/session is created. We only need the email + consent.
- Segment tag: `isPremium` read from `StoreManager` at signup time is included so the
  list can distinguish paying subscribers from free users from day one.

**Shared backend (build now):**

```
App (any Delicious app)
   │  POST https://delicious.works/api/subscribe
   │  { email, app:"shabbatclock", locale, isPremium, appVersion, consent:true }
   │  Firebase App Check (App Attest, iOS 26) attests the request
   ▼
/api/subscribe ── Vercel serverless function (existing delicious.works project) ──
   │  1. Validate: email format · app in allowlist · consent == true · App Check token
   │     (verified via Firebase Admin SDK, works from any backend — not Functions-only)
   │  2. Write consent audit → Firestore (project: deliciousapps, Spark/free plan)
   │        subscribers/{app}/contacts/{emailHash}
   │        { email, app, isPremium, locale, source, consentedAt, appVersion }
   │  3. Upsert contact → Loops.so API
   │        properties: appName, locale, isPremium, subscribed=true
   ▼
   200 OK  (idempotent — re-subscribe is a safe upsert)
```

- **Why Vercel instead of a Firebase Cloud Function:** Cloud Functions deployment
  (1st or 2nd gen) requires the Blaze pay-as-you-go plan enabled — a payment method
  on file — regardless of whether real usage stays within the free quota (verified,
  not assumed: Blaze is required to deploy at all, since the build pipeline touches
  billed services). Firestore itself has no such requirement on the Spark/free plan.
  `delicious.works` is already hosted on Vercel's free Hobby tier, which runs
  serverless functions with outbound network access at no cost and no card — so the
  endpoint lives there instead, using the Firebase Admin SDK (service-account
  credential, stored as a Vercel env var) purely to reach Firestore. Functionally
  equivalent to the Cloud Function design; just a different, genuinely free host.
- **Why a function in front of Loops (not app → Loops directly):**
  - Loops API key stays server-side (Vercel env var) — not extractable from the binary.
  - ESP is swappable later without an app update; the app's contract is just the endpoint.
  - Central place to enforce consent + write the audit record + apply segment tags.
  - One integration reused by every Delicious app via the `app` tag.
- **Consent/compliance:** the Firestore record is the durable proof-of-opt-in for
  marketing email (GDPR/CAN-SPAM), independent of Loops (which holds live subscription
  state). `emailHash` (e.g. SHA-256 of lowercased email) is the doc id for idempotent
  upserts; the plaintext email is a field for export/debugging.
- **Abuse prevention:** Firebase App Check (App Attest on iOS 26) gates the endpoint
  so only genuine app installs can call it. No shared secret needed.
- **Reply handling:** newsletter campaigns set a Reply-To distinct from the verified
  From address (e.g. From `hello@mail.delicious.works`, Reply-To the operator's
  personal inbox) — Loops supports this natively, no extra infrastructure needed.
- **Unsubscribe:** handled entirely by Loops (hosted page + list-unsubscribe header).
  The app builds nothing.

### Where things live / graduate to

| Piece | Home |
|---|---|
| `WhatsNewConfig` content | ShabbatClock (per release) |
| What's New / Review / Auth modules | DeliciousKit (already built) |
| `Newsletter.swift` client | **New in DeliciousKit** (built post-refactor) |
| `/api/subscribe` function + Firestore schema + Loops adapter | **New shared Delicious backend** (Vercel + Firestore) |
| Pipeline capture | `delicious/CLAUDE.md` Lessons Learned + new `shared/skills/delicious-newsletter.md` |

## Infrastructure decisions (confirmed)

- **ESP:** Loops.so.
- **Backend scope:** one shared service for all Delicious apps, keyed by an `app` tag.
- **Shared Firebase project: `deliciousapps`** (created 2026-07-09, Spark/free plan —
  hosts Firestore only, no Cloud Functions/Blaze needed since the endpoint runs on
  Vercel instead). Name doubles as a nice match for the existing
  `cohen72/delicious.apps` GitHub repo.
- **Sending domain: a subdomain of `delicious.works`** (e.g. `mail.delicious.works`),
  **not a new domain purchase.** `deliciousapps.com` was considered (verified
  unregistered, 2026-07-09) for a cleaner consumer-facing "From" address, but
  deliberately deferred — validate the newsletter itself first with infrastructure
  already owned rather than buying new domains before there's a proven need (see
  the operator's own standing MVP-scope-discipline preference: ship on what you
  have, invest further only where signal exists). Revisit a dedicated consumer
  domain later if/when the newsletter proves out. Loops recommends a subdomain
  over the root domain regardless (isolates sending reputation + DNS records from
  the website), so `mail.delicious.works` is the concrete pick either way.

## Error handling

- **Signup POST fails (network / 5xx):** show a non-blocking error, keep the Settings
  row in its un-subscribed state so the user can retry. Never lose the user's tap
  silently. Onboarding still advances (never trap the user on a failed newsletter step).
- **Function validation failure (bad email / missing consent):** 400, app surfaces a
  friendly "couldn't sign you up" message.
- **App Check failure:** 401/403; app treats as a transient error and offers retry.
- **Loops upsert fails after Firestore write:** function returns 502; the Firestore
  consent record still exists, so a later reconciliation job can replay to Loops. The
  operation is idempotent, so client retry is safe.
- **What's New / Review:** best-effort, non-blocking; any failure is silent (these are
  enhancements, not core flows).

## Testing

- **Backend:** unit-test the Cloud Function's validation branches (bad email, missing
  consent, unknown app), the Firestore write shape, and the Loops adapter (mocked).
  Test idempotency (same email twice → one contact, updated). Use the Firebase
  emulator suite for Firestore + Functions locally.
- **What's New:** verify the sheet shows once per version and not again after "seen"
  is recorded; verify EN/HE localization.
- **Review:** verify the gate (positive event required, session/version/year caps).
- **Newsletter client (post-refactor):** verify the local "already subscribed" flag
  suppresses re-prompt; verify failure keeps retry available; verify `isPremium` is
  sent correctly for both free and premium states.

## Build order

1. **Now:** shared backend — provision `delicious-shared` (with operator confirmation),
   write `subscribeToUpdates`, Firestore schema, Loops adapter, App Check. Test via
   emulator + a real Loops sandbox contact.
2. **Now (parallel):** What's New content + Review trigger wiring can be prepped, but
   both ship via the DeliciousKit dependency add, so they land with step 3.
3. **After DeliciousKit refactor lands:** add DeliciousKit as a ShabbatClock dependency;
   build `Newsletter.swift` client in DeliciousKit; wire the onboarding step + Settings
   row; wire What's New + Review. Ship as ShabbatClock 1.0.5.

## Pipeline leverage (dogfooding capture)

Per the operator's standing instruction, every reusable thing here graduates into the
Delicious pipeline:
- `Newsletter.swift` → DeliciousKit (reused by every app).
- `subscribeToUpdates` + Firestore schema + Loops adapter → shared Delicious backend.
- A new `shared/skills/delicious-newsletter.md` documenting the opt-in + consent pattern.
- Lessons captured in `delicious/CLAUDE.md` and cross-app conventions in `apps/CLAUDE.md`.

import Foundation
import Mixpanel
import FirebaseAnalytics
import FirebaseInstallations

/// Single funnel for every analytics event in the app.
///
/// **Privacy & Guideline 5.1.2 posture**: the service is configured for
/// non-tracking product analytics — no IDFA, no ad-attribution, no data brokers,
/// no third-party sharing. App Privacy → "Used to Track You" answers remain **No**
/// and no ATT prompt is required.
///
/// **Rules**:
/// - Never call `Mixpanel.mainInstance().track(...)` directly. Always go through
///   ``Analytics/track(_:)`` so events stay type-checked and consistent.
/// - Event payloads MUST NOT contain user-provided free text (alarm labels,
///   custom sound names, location strings, email, etc.). Only metadata buckets.
/// - Add a new case to ``AnalyticsEvent`` to introduce a new event. No strings
///   scattered across views.
@MainActor
enum Analytics {

    // MARK: - Configuration

    /// Called once on app launch. Reads the Mixpanel project token from
    /// `Secrets.plist` → `MixpanelProjectToken`. No-ops if the token is missing
    /// (e.g., first checkout without Secrets.plist), so the app still runs.
    static func configure() {
        guard let token = SecretsLoader.mixpanelToken, !token.isEmpty else {
            print("[Analytics] No MixpanelProjectToken in Secrets.plist — analytics disabled.")
            return
        }

        // `trackAutomaticEvents: false` — we only send events we explicitly declare.
        // This keeps the privacy surface small and matches our "no automatic tracking" stance.
        Mixpanel.initialize(token: token, trackAutomaticEvents: false)

        // Opt-out of session replay / surveys etc. by default — product analytics only.
        // `optOutTracking` is OFF (we DO want our explicit events), but automatic
        // IDFA/ad-network integrations are not enabled on this SDK path.
        configured = true

        // Mirror the Firebase Installation ID as a user property so Remote Config
        // audience conditions can target individual installs (e.g. "give this
        // user a higher free_alarm_limit"). Async; user property is set when ready.
        // Also cached for inclusion in support email footers (AppURLs).
        Installations.installations().installationID { id, _ in
            guard let id else { return }
            FirebaseAnalytics.Analytics.setUserProperty(id, forName: "install_id")
            AppURLs.cachedInstallID = id
        }
    }

    /// Fetch the Firebase Installation ID for display purposes (e.g. Settings → "Your User ID").
    /// Returns nil on failure. Async because Firebase computes/caches it lazily.
    static func installationID() async -> String? {
        try? await Installations.installations().installationID()
    }

    private(set) static var configured: Bool = false

    // MARK: - Super Properties

    /// Sets cross-event properties. Call once on app launch and whenever these
    /// values change (e.g. when the user subscribes, changes language, etc.).
    static func setSuperProperties(
        isPremium: Bool,
        appLanguage: String,
        appearanceMode: String,
        alarmCount: Int,
        hasLocation: Bool
    ) {
        guard configured else { return }
        let props: Properties = [
            "is_premium": isPremium,
            "app_language": appLanguage,
            "appearance_mode": appearanceMode,
            "alarm_count": alarmCount,
            "has_location": hasLocation,
        ]
        Mixpanel.mainInstance().registerSuperProperties(props)

        // Firebase user properties (mirrored). Values must be strings, max 36 chars.
        FirebaseAnalytics.Analytics.setUserProperty(String(isPremium), forName: "is_premium")
        FirebaseAnalytics.Analytics.setUserProperty(appLanguage, forName: "app_language")
        FirebaseAnalytics.Analytics.setUserProperty(appearanceMode, forName: "appearance_mode")
        FirebaseAnalytics.Analytics.setUserProperty(String(alarmCount), forName: "alarm_count")
        FirebaseAnalytics.Analytics.setUserProperty(String(hasLocation), forName: "has_location")
    }

    /// Update a single super property without resetting the rest. Useful for
    /// incremental state changes (e.g. a new alarm was created).
    static func setSuperProperty(_ key: String, value: MixpanelType) {
        guard configured else { return }
        Mixpanel.mainInstance().registerSuperProperties([key: value])
        FirebaseAnalytics.Analytics.setUserProperty(firebaseUserPropertyString(value), forName: key)
    }

    /// Convert a Mixpanel value to a Firebase user property string (max 36 chars).
    private static func firebaseUserPropertyString(_ value: MixpanelType) -> String {
        let str: String
        switch value {
        case let v as Bool:   str = String(v)
        case let v as Int:    str = String(v)
        case let v as Double: str = String(v)
        case let v as String: str = v
        default:              str = "\(value)"
        }
        return String(str.prefix(36))
    }

    // MARK: - Tracking

    /// The ONLY way events are sent. Callers pass a typed `AnalyticsEvent`;
    /// this method resolves it to name + properties and forwards to Mixpanel
    /// AND Firebase Analytics so funnels and conversions are visible in both
    /// providers, and Remote Config audiences can target on event behavior.
    static func track(_ event: AnalyticsEvent) {
        guard configured else { return }
        Mixpanel.mainInstance().track(event: event.name, properties: event.properties)
        FirebaseAnalytics.Analytics.logEvent(event.name, parameters: firebaseParameters(from: event.properties))
    }

    /// Reset analytics identity — call if the user ever signs out of an account.
    /// Currently the app is anonymous-only, so this is a placeholder.
    static func reset() {
        guard configured else { return }
        Mixpanel.mainInstance().reset()
        FirebaseAnalytics.Analytics.resetAnalyticsData()
    }

    /// Convert a Mixpanel `Properties` dictionary to Firebase-compatible event
    /// parameters. Firebase accepts String, Int (NSNumber), Double, Bool. Anything
    /// else gets stringified. Values are clamped to 100 chars (Firebase's per-param limit).
    private static func firebaseParameters(from properties: Properties?) -> [String: Any]? {
        guard let properties, !properties.isEmpty else { return nil }
        var out: [String: Any] = [:]
        for (key, value) in properties {
            switch value {
            case let v as Bool:   out[key] = v
            case let v as Int:    out[key] = v
            case let v as Double: out[key] = v
            case let v as String: out[key] = String(v.prefix(100))
            default:              out[key] = String(String(describing: value).prefix(100))
            }
        }
        return out
    }
}

// MARK: - Secrets Loader

/// Reads values from `Secrets.plist`. Missing file returns nil silently so
/// builds without the plist (fresh checkouts, CI without secrets) still run.
enum SecretsLoader {
    static var mixpanelToken: String? {
        guard
            let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            return nil
        }
        return dict["MixpanelProjectToken"] as? String
    }
}

// MARK: - Event Taxonomy

/// Every event the app can emit. Adding a new event = adding a case here.
///
/// **Naming**: `domain_action` — e.g. `alarm_created`, `paywall_viewed`. Use
/// snake_case so Mixpanel's default event browser groups them alphabetically
/// by domain.
enum AnalyticsEvent {

    // MARK: Activation (onboarding funnel)

    case onboardingStarted
    case onboardingPageViewed(page: OnboardingPage)
    case onboardingPermissionPrompted(permission: Permission)
    case onboardingPermissionGranted(permission: Permission)
    case onboardingPermissionDenied(permission: Permission)
    case onboardingCompleted(
        alarmAuthorized: Bool,
        notificationsAuthorized: Bool,
        locationAuthorized: Bool
    )

    // MARK: Core engagement

    /// Fired when a user creates an alarm. `source` distinguishes manual vs zman.
    case alarmCreated(
        source: AlarmSource,
        zmanType: String?,
        hasRepeat: Bool,
        repeatDayCount: Int,
        soundCategory: String,
        timeBucket: TimeBucket
    )
    case alarmEdited(source: AlarmSource)
    case alarmDeleted(source: AlarmSource)
    case alarmEnabled(source: AlarmSource)
    case alarmDisabled(source: AlarmSource)
    case alarmFired(source: AlarmSource)
    case alarmStopped(source: AlarmSource, method: StopMethod)

    case zmanimViewed
    case locationChanged(method: LocationMethod)
    case appOpened
    case tabSwitched(tab: Tab)

    // MARK: Monetization funnel

    /// The single most important event for revenue analysis. `trigger` tells us
    /// which feature pushed the user to consider upgrading.
    case paywallViewed(trigger: PaywallTrigger)
    case paywallPlanSelected(plan: Plan)
    case purchaseStarted(plan: Plan)
    case purchaseCompleted(plan: Plan)
    case purchaseFailed(plan: Plan, reason: String)
    case purchaseCancelled(plan: Plan)
    case purchaseRestored

    /// Fired when a free-tier user hits a premium wall (2-alarm limit, locked sound, etc.).
    /// Pairs with `paywallViewed` for funnel analysis: how many who hit the limit then
    /// saw the paywall, then purchased?
    case freeLimitHit(feature: GatedFeature)

    // MARK: - Associated Types

    enum OnboardingPage: String { case welcome, alarms, ringSetup, notifications, location }
    enum Permission: String { case alarms, notifications, location }
    enum AlarmSource: String { case manual, zman }
    enum StopMethod: String { case auto, manual, snoozed }
    enum LocationMethod: String { case gps, manual }
    enum Tab: String { case clock, alarms, zmanim, settings }
    enum PaywallTrigger: String {
        case alarmLimit = "alarm_limit"
        case zmanAlarmLimit = "zman_alarm_limit"
        case lockedSound = "locked_sound"
        case settings
        case customSounds = "custom_sounds"
    }
    enum Plan: String { case weekly, yearly }
    enum GatedFeature: String { case alarm, sound, zmanAlarm = "zman_alarm", customSound = "custom_sound" }

    /// Coarse bucket for alarm time-of-day — avoids logging the exact wake time.
    enum TimeBucket: String {
        case earlyMorning = "early_morning"   // 4–7
        case morning                          // 7–11
        case midday                           // 11–14
        case afternoon                        // 14–18
        case evening                          // 18–22
        case night                            // 22–4

        static func bucket(hour: Int) -> TimeBucket {
            switch hour {
            case 4..<7: return .earlyMorning
            case 7..<11: return .morning
            case 11..<14: return .midday
            case 14..<18: return .afternoon
            case 18..<22: return .evening
            default: return .night
            }
        }
    }

    // MARK: - Event → Name/Properties

    var name: String {
        switch self {
        case .onboardingStarted: return "onboarding_started"
        case .onboardingPageViewed: return "onboarding_page_viewed"
        case .onboardingPermissionPrompted: return "onboarding_permission_prompted"
        case .onboardingPermissionGranted: return "onboarding_permission_granted"
        case .onboardingPermissionDenied: return "onboarding_permission_denied"
        case .onboardingCompleted: return "onboarding_completed"
        case .alarmCreated: return "alarm_created"
        case .alarmEdited: return "alarm_edited"
        case .alarmDeleted: return "alarm_deleted"
        case .alarmEnabled: return "alarm_enabled"
        case .alarmDisabled: return "alarm_disabled"
        case .alarmFired: return "alarm_fired"
        case .alarmStopped: return "alarm_stopped"
        case .zmanimViewed: return "zmanim_viewed"
        case .locationChanged: return "location_changed"
        case .appOpened: return "app_opened"
        case .tabSwitched: return "tab_switched"
        case .paywallViewed: return "paywall_viewed"
        case .paywallPlanSelected: return "paywall_plan_selected"
        case .purchaseStarted: return "purchase_started"
        case .purchaseCompleted: return "purchase_completed"
        case .purchaseFailed: return "purchase_failed"
        case .purchaseCancelled: return "purchase_cancelled"
        case .purchaseRestored: return "purchase_restored"
        case .freeLimitHit: return "free_limit_hit"
        }
    }

    var properties: Properties? {
        switch self {
        case .onboardingStarted, .zmanimViewed, .appOpened, .purchaseRestored:
            return nil

        case .onboardingPageViewed(let page):
            return ["page": page.rawValue]

        case .onboardingPermissionPrompted(let p),
             .onboardingPermissionGranted(let p),
             .onboardingPermissionDenied(let p):
            return ["permission": p.rawValue]

        case .onboardingCompleted(let alarm, let notif, let loc):
            return [
                "alarm_authorized": alarm,
                "notifications_authorized": notif,
                "location_authorized": loc,
            ]

        case .alarmCreated(let source, let zmanType, let hasRepeat, let repeatCount, let soundCategory, let timeBucket):
            var props: Properties = [
                "source": source.rawValue,
                "has_repeat": hasRepeat,
                "repeat_day_count": repeatCount,
                "sound_category": soundCategory,
                "time_bucket": timeBucket.rawValue,
            ]
            if let zmanType { props["zman_type"] = zmanType }
            return props

        case .alarmEdited(let source),
             .alarmDeleted(let source),
             .alarmEnabled(let source),
             .alarmDisabled(let source),
             .alarmFired(let source):
            return ["source": source.rawValue]

        case .alarmStopped(let source, let method):
            return ["source": source.rawValue, "method": method.rawValue]

        case .locationChanged(let method):
            return ["method": method.rawValue]

        case .tabSwitched(let tab):
            return ["tab": tab.rawValue]

        case .paywallViewed(let trigger):
            return ["trigger": trigger.rawValue]

        case .paywallPlanSelected(let plan),
             .purchaseStarted(let plan),
             .purchaseCompleted(let plan),
             .purchaseCancelled(let plan):
            return ["plan": plan.rawValue]

        case .purchaseFailed(let plan, let reason):
            return ["plan": plan.rawValue, "reason": reason]

        case .freeLimitHit(let feature):
            return ["feature": feature.rawValue]
        }
    }
}

import DeliciousKit

/// Shared instance of DeliciousKit's gated review prompter. The "positive
/// event" for ShabbatClock is an alarm firing and auto-stopping cleanly on
/// its own — the app's actual core promise succeeding — not a manual stop
/// button (this app deliberately has almost no path to one) or raw session
/// count. See AlarmKitService's two auto-stop completion points.
let reviewPrompter = ReviewPrompter()

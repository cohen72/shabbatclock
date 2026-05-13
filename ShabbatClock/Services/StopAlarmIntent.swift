import AppIntents
import AlarmKit

/// App Intent invoked when the user taps Stop on a firing AlarmKit alarm.
///
/// Wired to the main alarm's `stopIntent` in `AlarmManager.AlarmConfiguration`. iOS
/// runs `perform()` directly when the user slides Stop — even if our app is fully
/// suspended or never launched. That makes this the reliable place to cancel the
/// paired silencer alarm so it doesn't fire seconds later as a "ghost" sound.
///
/// The silencer's UUID is baked into the intent at schedule time (see `scheduleAlarm`
/// in `AlarmKitService`), so `perform()` doesn't need any SwiftData lookup — it can
/// run in iOS's lightweight intent process and finish without our app waking up.
struct StopAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop Alarm"

    @Parameter(title: "Alarm ID")
    var alarmID: String

    /// AlarmKit ID of the paired silencer alarm. Empty string when no silencer was
    /// scheduled (e.g., scheduling failed). Stored as a string because AppIntents
    /// parameters don't support optional UUIDs cleanly.
    @Parameter(title: "Silencer ID")
    var silencerID: String

    /// True when this intent is wired to a silencer alarm's own Stop button (rather
    /// than to a user-facing main alarm). For silencers, we call `cancel(id:)` on
    /// `alarmID` so any `.relative .weekly` schedule is fully removed — `stop(id:)`
    /// alone leaves the next occurrence scheduled, which is how a dismissed silencer
    /// can re-fire week after week as a zombie alarm.
    ///
    /// Defaults to false so existing intents (decoded from older alarms still
    /// scheduled in alarmsd before this fix shipped) behave as before.
    @Parameter(title: "Is Silencer", default: false)
    var isSilencer: Bool

    init() {}

    init(alarmID: UUID, silencerID: UUID? = nil, isSilencer: Bool = false) {
        self.alarmID = alarmID.uuidString
        self.silencerID = silencerID?.uuidString ?? ""
        self.isSilencer = isSilencer
    }

    func perform() async throws -> some IntentResult {
        if let uuid = UUID(uuidString: alarmID) {
            if isSilencer {
                // Silencers must be cancelled, not just stopped — otherwise a recurring
                // `.weekly` schedule survives dismissal and keeps firing.
                try? AlarmManager.shared.cancel(id: uuid)
            } else {
                try? AlarmManager.shared.stop(id: uuid)
            }
        }
        // Cancel the paired silencer so it doesn't fire later as a "ghost" sound.
        if !silencerID.isEmpty, let uuid = UUID(uuidString: silencerID) {
            try? AlarmManager.shared.cancel(id: uuid)
        }
        return .result()
    }
}

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

    init() {}

    init(alarmID: UUID, silencerID: UUID? = nil) {
        self.alarmID = alarmID.uuidString
        self.silencerID = silencerID?.uuidString ?? ""
    }

    func perform() async throws -> some IntentResult {
        if let uuid = UUID(uuidString: alarmID) {
            try? AlarmManager.shared.stop(id: uuid)
        }
        // Cancel the paired silencer so it doesn't fire later as a "ghost" sound.
        if !silencerID.isEmpty, let uuid = UUID(uuidString: silencerID) {
            try? AlarmManager.shared.cancel(id: uuid)
        }
        return .result()
    }
}

import AppIntents
import AlarmKit

/// App Intent that stops a firing AlarmKit alarm.
/// Used as the `stopIntent` on AlarmConfiguration so the system can auto-stop
/// the alarm after the user's chosen duration — critical for Shabbat use where
/// the user won't be interacting with their phone.
struct StopAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop Alarm"

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init() {}

    init(alarmID: UUID) {
        self.alarmID = alarmID.uuidString
    }

    func perform() async throws -> some IntentResult {
        if let uuid = UUID(uuidString: alarmID) {
            try? AlarmManager.shared.stop(id: uuid)
        }
        return .result()
    }
}

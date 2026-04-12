import AlarmKit
import Foundation

/// App-specific metadata attached to AlarmKit alarms.
/// Flows through to Live Activity for rich display in Dynamic Island and Lock Screen.
struct ShabbatAlarmMetadata: AlarmMetadata {
    let label: String
    let isShabbatAlarm: Bool
    let soundCategory: String
}

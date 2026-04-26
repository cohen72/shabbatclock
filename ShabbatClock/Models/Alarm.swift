import Foundation
import SwiftData

@Model
final class Alarm {
    var id: UUID
    var hour: Int
    var minute: Int
    var isEnabled: Bool
    var label: String
    var soundName: String
    var repeatDays: [Int]  // 0=Sunday, 1=Monday, ..., 6=Saturday
    var createdAt: Date
    var lastFiredAt: Date?
    var alarmKitID: UUID?
    /// AlarmKit ID of the "silencer" alarm scheduled at fireTime + duration.
    /// The silencer is a silent AlarmKit alarm that fires shortly after the main alarm;
    /// iOS treats it as a new alarm and (as a side effect) silences the original ringing.
    /// This is the auto-stop mechanism for AlarmKit alarms, since we can't run code
    /// while the app is suspended to call AlarmManager.stop().
    var silencerAlarmKitID: UUID?
    var snoozeDurationSecondsValue: Int?
    var snoozeEnabledValue: Bool?
    var alarmDurationSecondsValue: Int?

    // MARK: - Zman Linkage
    /// Raw value of ZmanimService.ZmanType (e.g., "shma", "netz"). Nil for manually created alarms.
    var zmanTypeRawValue: String?
    /// How many minutes before the zman this alarm is set (0, 5, 10, 15, 30). Nil for manually created alarms.
    var zmanMinutesBefore: Int?

    /// Snooze duration in seconds (defaults to 300 / 5 min for migrated alarms).
    var snoozeDurationSeconds: Int {
        get { snoozeDurationSecondsValue ?? 300 }
        set { snoozeDurationSecondsValue = newValue }
    }

    /// Whether snooze is enabled. Always false app-wide for now — the UI hides snooze
    /// entirely, AlarmKitService ignores the flag when scheduling, and all save paths
    /// persist false. Field is retained so snooze can be re-enabled later without a
    /// schema migration (e.g., weekday alarms).
    var snoozeEnabled: Bool {
        get { snoozeEnabledValue ?? false }
        set { snoozeEnabledValue = newValue }
    }

    /// How long the alarm should ring before auto-stopping (defaults to 60s).
    var alarmDurationSeconds: Int {
        get { alarmDurationSecondsValue ?? 60 }
        set { alarmDurationSecondsValue = newValue }
    }

    init(
        id: UUID = UUID(),
        hour: Int = 7,
        minute: Int = 0,
        isEnabled: Bool = true,
        label: String = String(localized: "Alarm"),
        soundName: String = "Shalom Aleichem",
        repeatDays: [Int] = [],
        createdAt: Date = Date(),
        lastFiredAt: Date? = nil,
        alarmKitID: UUID? = nil,
        snoozeDurationSeconds: Int = 0,
        snoozeEnabled: Bool = false,
        alarmDurationSeconds: Int = 60
    ) {
        self.id = id
        self.hour = hour
        self.minute = minute
        self.isEnabled = isEnabled
        self.label = label
        self.soundName = soundName
        self.repeatDays = repeatDays
        self.createdAt = createdAt
        self.lastFiredAt = lastFiredAt
        self.alarmKitID = alarmKitID
        self.snoozeDurationSecondsValue = snoozeDurationSeconds
        self.snoozeEnabledValue = snoozeEnabled
        self.alarmDurationSecondsValue = alarmDurationSeconds
    }

    // MARK: - Computed Properties

    /// Numeric time portion ("7:30" or "19:30"), no AM/PM.
    /// Renders in 12h or 24h based on the user's iOS time-format preference.
    var timeString: String {
        TimeFormatter.timeOnly(TimeFormatter.date(hour: hour, minute: minute))
    }

    /// Localized AM/PM marker, or empty string when the user is on 24-hour time.
    /// Views that render this as a separate styled view should check for empty
    /// and hide the label entirely.
    var periodString: String {
        TimeFormatter.period(TimeFormatter.date(hour: hour, minute: minute)) ?? ""
    }

    /// Full localized time — "7:30 AM" in 12h, "19:30" in 24h.
    var formattedTime: String {
        TimeFormatter.fullTime(TimeFormatter.date(hour: hour, minute: minute))
    }

    var repeatDaysString: String {
        if repeatDays.isEmpty {
            return String(localized: "One time")
        }
        if repeatDays.count == 7 {
            return String(localized: "Every day")
        }
        if repeatDays == [0, 6] || repeatDays == [6, 0] {
            return String(localized: "Weekends")
        }
        if Set(repeatDays) == Set([1, 2, 3, 4, 5]) {
            return String(localized: "Weekdays")
        }
        // Use locale-aware day names — very short for Hebrew (א, ב, ג), short for English (Sun, Mon)
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.current.effectiveLocale
        let isHebrew = formatter.locale.language.languageCode?.identifier == "he"
        let symbols = (isHebrew ? formatter.veryShortWeekdaySymbols : formatter.shortWeekdaySymbols)
            ?? ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let sortedDays = repeatDays.sorted()
        return sortedDays.map { symbols[$0] }.joined(separator: ", ")
    }

    var isShabbatAlarm: Bool {
        repeatDays.contains(6) // Saturday
    }

    // MARK: - Next Fire Date Calculation

    func nextFireDate(from date: Date = Date()) -> Date? {
        guard isEnabled else { return nil }

        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        components.hour = hour
        components.minute = minute
        components.second = 0

        guard let alarmTimeToday = calendar.date(from: components) else { return nil }

        // If no repeat days, it's a one-time alarm
        if repeatDays.isEmpty {
            // If the time already passed today, schedule for tomorrow
            if alarmTimeToday <= date {
                return calendar.date(byAdding: .day, value: 1, to: alarmTimeToday)
            }
            return alarmTimeToday
        }

        // Find the next matching day
        for dayOffset in 0..<8 {
            guard let candidateDate = calendar.date(byAdding: .day, value: dayOffset, to: alarmTimeToday) else { continue }

            // Skip if it's today and the time has passed
            if dayOffset == 0 && alarmTimeToday <= date {
                continue
            }

            let weekday = calendar.component(.weekday, from: candidateDate) - 1 // Convert to 0-based (Sunday = 0)

            if repeatDays.contains(weekday) {
                return candidateDate
            }
        }

        return nil
    }

    // MARK: - Check if Should Fire

    func shouldFire(at date: Date = Date()) -> Bool {
        guard isEnabled else { return false }

        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: date)
        let currentMinute = calendar.component(.minute, from: date)
        let currentWeekday = calendar.component(.weekday, from: date) - 1

        // Check if time matches
        guard currentHour == hour && currentMinute == minute else { return false }

        // Check if already fired this minute
        if let lastFired = lastFiredAt {
            let lastFiredMinute = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: lastFired)
            let currentMinuteComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            if lastFiredMinute == currentMinuteComponents {
                return false
            }
        }

        // Check repeat days
        if repeatDays.isEmpty {
            return true // One-time alarm
        }

        return repeatDays.contains(currentWeekday)
    }
}

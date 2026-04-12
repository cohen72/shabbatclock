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

    init(
        id: UUID = UUID(),
        hour: Int = 7,
        minute: Int = 0,
        isEnabled: Bool = true,
        label: String = String(localized: "Alarm"),
        soundName: String = "Lecha Dodi",
        repeatDays: [Int] = [],
        createdAt: Date = Date(),
        lastFiredAt: Date? = nil
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
    }

    // MARK: - Computed Properties

    var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        let date = Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? Date()
        return formatter.string(from: date)
    }

    var periodString: String {
        hour < 12 ? "AM" : "PM"
    }

    var formattedTime: String {
        "\(timeString) \(periodString)"
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

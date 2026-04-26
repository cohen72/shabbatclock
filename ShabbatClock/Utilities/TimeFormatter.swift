import Foundation
import SwiftUI

/// User preference for the time format. Stored in `@AppStorage("timeFormat")`.
/// `.system` defers to iOS Settings → General → Date & Time → 24-Hour Time
/// (on regions that expose that toggle). `.twelveHour` / `.twentyFourHour`
/// force the format regardless of region or system setting.

enum TimeFormat: String, CaseIterable, Identifiable {
    case system
    case twelveHour = "12"
    case twentyFourHour = "24"

    var id: String { rawValue }

    /// Localized label for the Settings picker.
    var displayName: String {
        switch self {
        case .system: return AppLanguage.localized("System")
        case .twelveHour: return AppLanguage.localized("12-hour")
        case .twentyFourHour: return AppLanguage.localized("24-hour")
        }
    }
}

/// Centralized time formatting that respects either the user's in-app preference
/// or iOS's 24-Hour Time setting.
///
/// ## Format resolution
/// - `TimeFormat.system` → reads `Locale.autoupdatingCurrent` via the `"j"` template,
///   which honors iOS Settings → General → Date & Time → 24-Hour Time.
/// - `TimeFormat.twelveHour` → forces `"h:mm a"`, bypassing system setting.
/// - `TimeFormat.twentyFourHour` → forces `"HH:mm"`, bypassing system setting.
///
/// ## Why an override exists
/// On some regions (notably United States), iOS hides the 24-Hour Time toggle
/// entirely. Users who want 24h on US region, or who want 12h while in a 24h
/// region, have no system-level way to change it — we expose it in-app.
enum TimeFormatter {
    /// Reads the user's stored preference from UserDefaults.
    /// Usable outside SwiftUI views where `@AppStorage` isn't available.
    static var userPreference: TimeFormat {
        let raw = UserDefaults.standard.string(forKey: "timeFormat") ?? TimeFormat.system.rawValue
        return TimeFormat(rawValue: raw) ?? .system
    }

    /// Whether the resolved time format is 24-hour (either forced or system-derived).
    /// Views use this to decide whether to render a separate AM/PM label.
    static var is24Hour: Bool {
        switch userPreference {
        case .twelveHour: return false
        case .twentyFourHour: return true
        case .system:
            // DateFormatter.dateFormat(fromTemplate:) returns a pattern without "a"
            // when the locale's 24-Hour Time setting is on.
            let template = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .autoupdatingCurrent) ?? ""
            return !template.contains("a")
        }
    }

    /// Formats the numeric portion of a time without AM/PM — "7:30" or "19:30".
    static func timeOnly(_ date: Date) -> String {
        let formatter = makeFormatter()
        // Strip the AM/PM marker so we can render it separately (or hide it in 24h mode).
        let pattern = (formatter.dateFormat ?? "")
            .replacingOccurrences(of: "a", with: "")
            .trimmingCharacters(in: .whitespaces)
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    /// Localized AM/PM for the given date, or `nil` when rendering 24-hour time.
    /// Use this for UIs that render the period as a separate styled view.
    static func period(_ date: Date) -> String? {
        guard !is24Hour else { return nil }
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = "a"
        return formatter.string(from: date)
    }

    /// Full localized time — "7:30 AM" in 12h mode, "19:30" in 24h mode.
    /// Use when the time is rendered as a single string (analytics, subtitles, etc.).
    static func fullTime(_ date: Date) -> String {
        makeFormatter().string(from: date)
    }

    /// Builds a `Date` from hour/minute components (using today's date) for formatting.
    /// The calendar-date portion is irrelevant — the result is used as input to a formatter.
    static func date(hour: Int, minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? Date()
    }

    /// Builds a DateFormatter whose hour style matches the user's preference,
    /// overriding the system setting when the user has forced 12h or 24h.
    private static func makeFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        switch userPreference {
        case .system:
            formatter.setLocalizedDateFormatFromTemplate("jmm")
        case .twelveHour:
            formatter.dateFormat = "h:mm a"
        case .twentyFourHour:
            formatter.dateFormat = "HH:mm"
        }
        return formatter
    }
}

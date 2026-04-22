import UIKit
import UserNotifications

/// Schedules a local notification before Shabbat reminding the user to review
/// their alarms and confirm phone setup (silent mode + vibration off).
///
/// Tapping the notification opens the app to a Shabbat Checklist sheet
/// (see ContentView routing).
///
/// Configurable via Settings:
/// - On/Off toggle (`shabbatReminderEnabled`)
/// - How many minutes before candle lighting (`shabbatReminderMinutesBefore`)
@MainActor
final class ShabbatReminderService {
    static let shared = ShabbatReminderService()
    static let notificationID = "shabbat-reminder"

    private init() {}

    /// Reschedule the reminder based on current settings and next candle lighting time.
    /// Called on app launch, when settings change, and when zmanim recalculate.
    func reschedule() {
        // Cancel any existing reminder
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [Self.notificationID]
        )

        let enabled = UserDefaults.standard.bool(forKey: "shabbatReminderEnabled")
        // Default to true if key hasn't been set yet
        let isEnabled = UserDefaults.standard.object(forKey: "shabbatReminderEnabled") == nil ? true : enabled
        guard isEnabled else { return }

        let minutesBefore = UserDefaults.standard.integer(forKey: "shabbatReminderMinutesBefore")
        let effectiveMinutes = minutesBefore > 0 ? minutesBefore : 120 // Default 2 hours

        // Get next candle lighting time from ZmanimService
        guard let candleLighting = ZmanimService.shared.candleLightingTime else {
            // Zmanim not loaded yet — will be called again when they load
            return
        }

        let reminderDate = candleLighting.addingTimeInterval(-Double(effectiveMinutes * 60))

        // Only schedule if the reminder is in the future
        guard reminderDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = AppLanguage.localized("Shabbat Shalom!")
        content.body = AppLanguage.localized("Tap to review your alarms and confirm your phone is ready for Shabbat.")
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        // Mark this notification so the tap handler can open the Shabbat checklist
        content.userInfo = ["action": "openShabbatChecklist"]

        let triggerComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: reminderDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)

        let request = UNNotificationRequest(
            identifier: Self.notificationID,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[ShabbatReminder] Failed to schedule: \(error)")
            } else {
                print("[ShabbatReminder] Scheduled for \(reminderDate)")
            }
        }
    }
}

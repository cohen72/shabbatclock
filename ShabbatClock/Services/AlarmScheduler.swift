import SwiftUI
import SwiftData
import Combine
import UserNotifications

/// Manages alarm scheduling using local notifications as the primary delivery mechanism.
/// Uses critical alerts to bypass Do Not Disturb / Focus modes.
@MainActor
final class AlarmScheduler: NSObject, ObservableObject {
    static let shared = AlarmScheduler()

    @Published var isAlarmFiring: Bool = false
    @Published var firingAlarm: Alarm?
    @Published var shutoffCountdown: Int = 0
    @Published var nextAlarmDate: Date?

    private var checkTimer: Timer?
    private var countdownTimer: Timer?
    private var modelContext: ModelContext?

    // Notification constants
    static let alarmCategoryIdentifier = "ALARM_CATEGORY"
    static let dismissActionIdentifier = "DISMISS_ACTION"
    static let snoozeActionIdentifier = "SNOOZE_ACTION"
    static let snoozeDurationMinutes = 5

    private override init() {
        super.init()
        setupNotificationHandling()
    }

    // MARK: - Setup

    func configure(with modelContext: ModelContext) {
        self.modelContext = modelContext
        startMonitoring()
        rescheduleAllNotifications()
        updateNextAlarmDate()
    }

    private func setupNotificationHandling() {
        // Register notification category with actions
        let dismissAction = UNNotificationAction(
            identifier: Self.dismissActionIdentifier,
            title: "Dismiss",
            options: [.destructive]
        )
        let snoozeAction = UNNotificationAction(
            identifier: Self.snoozeActionIdentifier,
            title: "Snooze (\(Self.snoozeDurationMinutes) min)",
            options: []
        )
        let alarmCategory = UNNotificationCategory(
            identifier: Self.alarmCategoryIdentifier,
            actions: [snoozeAction, dismissAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([alarmCategory])

        // Set delegate to handle foreground presentation and actions
        UNUserNotificationCenter.current().delegate = self

        // Request permissions including critical alerts
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge, .criticalAlert]
        ) { granted, error in
            if granted {
                print("[AlarmScheduler] Notification permission granted (including critical alerts)")
            } else if let error = error {
                print("[AlarmScheduler] Notification permission error: \(error)")
            } else {
                // Critical alert may have been denied but regular alerts granted
                // Fall back to requesting without critical alerts
                UNUserNotificationCenter.current().requestAuthorization(
                    options: [.alert, .sound, .badge]
                ) { granted, _ in
                    print("[AlarmScheduler] Fallback notification permission: \(granted)")
                }
            }
        }
    }

    // MARK: - Monitoring (in-app alarm detection)

    /// Start monitoring for alarm times when app is in foreground.
    func startMonitoring() {
        stopMonitoring()

        checkTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkAlarms()
            }
        }

        if let timer = checkTimer {
            RunLoop.main.add(timer, forMode: .common)
        }

        print("[AlarmScheduler] Monitoring started")
    }

    func stopMonitoring() {
        checkTimer?.invalidate()
        checkTimer = nil
    }

    // MARK: - Alarm Checking

    private func checkAlarms() {
        guard !isAlarmFiring else { return }
        guard let modelContext = modelContext else { return }

        let descriptor = FetchDescriptor<Alarm>(
            predicate: #Predicate { $0.isEnabled }
        )

        do {
            let alarms = try modelContext.fetch(descriptor)
            let now = Date()

            for alarm in alarms {
                if alarm.shouldFire(at: now) {
                    fireAlarm(alarm)
                    break
                }
            }
        } catch {
            print("[AlarmScheduler] Failed to fetch alarms: \(error)")
        }
    }

    // MARK: - Fire Alarm (in-app)

    private func fireAlarm(_ alarm: Alarm) {
        guard !isAlarmFiring else { return }

        isAlarmFiring = true
        firingAlarm = alarm
        shutoffCountdown = 30

        alarm.lastFiredAt = Date()

        // Cancel the notification for this occurrence since we're handling it in-app
        removeNotification(for: alarm)

        // Disable one-time alarms
        if alarm.repeatDays.isEmpty {
            alarm.isEnabled = false
        }

        // Reschedule for next occurrence (repeating alarms)
        scheduleNotification(for: alarm)

        // Play the alarm sound
        if let sound = AlarmSound.sound(named: alarm.soundName) {
            AudioManager.shared.playAlarm(sound: sound, fadeIn: true)
        }

        // Start 30-second auto-shutoff
        startShutoffCountdown()

        updateNextAlarmDate()

        NotificationCenter.default.post(name: .alarmFired, object: alarm)

        print("[AlarmScheduler] Alarm fired: \(alarm.label) - auto shutoff in 30s")
    }

    // MARK: - Shutoff

    private func startShutoffCountdown() {
        countdownTimer?.invalidate()

        var remaining = 30
        shutoffCountdown = remaining

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            Task { @MainActor in
                remaining -= 1
                self?.shutoffCountdown = remaining

                if remaining <= 0 {
                    timer.invalidate()
                    self?.stopAlarm()
                }
            }
        }

        if let timer = countdownTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    /// Manually stop the currently firing alarm.
    func stopAlarm() {
        countdownTimer?.invalidate()
        countdownTimer = nil

        AudioManager.shared.stopAlarm(fadeOut: true)

        isAlarmFiring = false
        firingAlarm = nil
        shutoffCountdown = 0

        NotificationCenter.default.post(name: .alarmStopped, object: nil)

        print("[AlarmScheduler] Alarm stopped")
    }

    // MARK: - Snooze

    func snoozeAlarm(_ alarm: Alarm) {
        stopAlarm()

        // Schedule a one-shot notification for snooze duration
        let content = UNMutableNotificationContent()
        content.title = "Shabbat Clock"
        content.body = "\(alarm.label) (Snoozed)"
        content.categoryIdentifier = Self.alarmCategoryIdentifier
        content.sound = criticalSound(for: alarm)
        content.interruptionLevel = .critical
        content.userInfo = ["alarmId": alarm.id.uuidString]

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(Self.snoozeDurationMinutes * 60),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: "snooze-\(alarm.id.uuidString)",
            content: content,
            trigger: trigger
        )

        let snoozeMinutes = Self.snoozeDurationMinutes
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[AlarmScheduler] Failed to schedule snooze: \(error)")
            } else {
                print("[AlarmScheduler] Snooze scheduled for \(snoozeMinutes) minutes")
            }
        }
    }

    // MARK: - Next Alarm

    func updateNextAlarmDate() {
        guard let modelContext = modelContext else {
            nextAlarmDate = nil
            return
        }

        let descriptor = FetchDescriptor<Alarm>(
            predicate: #Predicate { $0.isEnabled }
        )

        do {
            let alarms = try modelContext.fetch(descriptor)
            let now = Date()
            let nextDates = alarms.compactMap { $0.nextFireDate(from: now) }
            nextAlarmDate = nextDates.min()

            if let next = nextAlarmDate {
                print("[AlarmScheduler] Next alarm: \(next)")
            }
        } catch {
            print("[AlarmScheduler] Failed to calculate next alarm: \(error)")
            nextAlarmDate = nil
        }
    }

    // MARK: - Notification Scheduling

    /// Schedule a local notification for an alarm's next fire date.
    func scheduleNotification(for alarm: Alarm) {
        guard alarm.isEnabled, let nextFire = alarm.nextFireDate() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Shabbat Clock"
        content.body = alarm.label
        content.categoryIdentifier = Self.alarmCategoryIdentifier
        content.sound = criticalSound(for: alarm)
        content.interruptionLevel = .critical
        content.userInfo = ["alarmId": alarm.id.uuidString]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: nextFire
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(
            identifier: alarm.id.uuidString,
            content: content,
            trigger: trigger
        )

        let alarmLabel = alarm.label
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[AlarmScheduler] Failed to schedule notification: \(error)")
            } else {
                print("[AlarmScheduler] Notification scheduled for \(alarmLabel) at \(nextFire)")
            }
        }
    }

    /// Remove scheduled notification for an alarm.
    func removeNotification(for alarm: Alarm) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [alarm.id.uuidString, "snooze-\(alarm.id.uuidString)"]
        )
    }

    /// Reschedule all enabled alarms. Called on app launch and after changes.
    func rescheduleAllNotifications() {
        guard let modelContext = modelContext else { return }

        // Remove all existing alarm notifications
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()

        let descriptor = FetchDescriptor<Alarm>(
            predicate: #Predicate { $0.isEnabled }
        )

        do {
            let alarms = try modelContext.fetch(descriptor)
            for alarm in alarms {
                scheduleNotification(for: alarm)
            }
            print("[AlarmScheduler] Rescheduled \(alarms.count) alarm notifications")
        } catch {
            print("[AlarmScheduler] Failed to reschedule notifications: \(error)")
        }
    }

    // MARK: - Critical Sound

    private func criticalSound(for alarm: Alarm) -> UNNotificationSound {
        // Try critical alert sound first (bypasses DND), fall back to regular
        let soundFileName = "\(alarm.soundName).m4a"
        // Critical alerts play at system-determined volume (0.0-1.0, we use 1.0)
        return UNNotificationSound.criticalSoundNamed(
            UNNotificationSoundName(soundFileName),
            withAudioVolume: 1.0
        )
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AlarmScheduler: UNUserNotificationCenterDelegate {
    /// Called when notification arrives while app is in foreground.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let alarmId = notification.request.content.userInfo["alarmId"] as? String

        Task { @MainActor in
            // If we have an alarm ID, fire it in-app instead of showing the notification
            if let alarmId = alarmId, let alarm = findAlarm(byId: alarmId) {
                fireAlarm(alarm)
                completionHandler([]) // Don't show notification banner, we handle it in-app
            } else {
                completionHandler([.banner, .sound])
            }
        }
    }

    /// Called when user interacts with the notification (taps, or uses an action).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let alarmId = response.notification.request.content.userInfo["alarmId"] as? String

        Task { @MainActor in
            switch response.actionIdentifier {
            case Self.dismissActionIdentifier, UNNotificationDismissActionIdentifier:
                // User dismissed - just stop if firing
                if isAlarmFiring {
                    stopAlarm()
                }

            case Self.snoozeActionIdentifier:
                // User snoozed
                if let alarmId = alarmId, let alarm = findAlarm(byId: alarmId) {
                    if isAlarmFiring {
                        snoozeAlarm(alarm)
                    } else {
                        // App was in background, schedule snooze directly
                        snoozeAlarm(alarm)
                    }
                }

            case UNNotificationDefaultActionIdentifier:
                // User tapped the notification - open the app and fire alarm UI
                if let alarmId = alarmId, let alarm = findAlarm(byId: alarmId) {
                    if !isAlarmFiring {
                        fireAlarm(alarm)
                    }
                }

            default:
                break
            }

            completionHandler()
        }
    }

    // MARK: - Helpers

    private func findAlarm(byId idString: String) -> Alarm? {
        guard let modelContext = modelContext,
              let uuid = UUID(uuidString: idString) else { return nil }

        let descriptor = FetchDescriptor<Alarm>(
            predicate: #Predicate { $0.id == uuid }
        )

        return try? modelContext.fetch(descriptor).first
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let alarmFired = Notification.Name("alarmFired")
    static let alarmStopped = Notification.Name("alarmStopped")
}

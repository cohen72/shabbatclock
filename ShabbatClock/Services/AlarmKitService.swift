import ActivityKit
import AlarmKit
import SwiftUI
import SwiftData
import UserNotifications

/// Manages alarm scheduling using AlarmKit (iOS 26+).
/// Replaces the old AlarmScheduler that used local notifications and background audio hacks.
/// AlarmKit alarms fire at the system level — they override Do Not Disturb, show in
/// Dynamic Island, and work even when the app is not running. Perfect for Shabbat use
/// where the phone sits untouched for 25+ hours.
@MainActor
@Observable
final class AlarmKitService: NSObject {
    static let shared = AlarmKitService()

    static let appGroupID = "group.works.delicious.shabbatclock"
    static let autoStopNotificationPrefix = "autostop-"
    static let autoStopCategoryID = "AUTO_STOP_CATEGORY"
    static let fallbackNotificationPrefix = "fallback-"

    private(set) var isAuthorized: Bool = false
    private(set) var isNotificationAuthorized: Bool = false
    private(set) var activeAlarms: [AlarmKit.Alarm] = []
    private(set) var nextAlarmDate: Date?

    /// True when AlarmKit was explicitly denied and alarms use local notifications as fallback.
    /// False when authorization is undetermined (user hasn't been asked yet).
    var isFallbackMode: Bool { !isAuthorized && hasBeenAskedForAuthorization }

    /// Whether the user has been prompted for AlarmKit authorization at least once.
    var hasBeenAskedForAuthorization: Bool {
        // If state is not .notDetermined, user has been asked
        AlarmManager.shared.authorizationState != .notDetermined
    }

    /// Maximum alarm duration in fallback mode (UNNotification sound limit).
    static let fallbackMaxDuration: Int = 30

    private var modelContext: ModelContext?

    /// Shared UserDefaults for widget communication.
    private let sharedDefaults = UserDefaults(suiteName: appGroupID)

    private override init() {
        super.init()
        setupNotificationHandling()
    }

    // MARK: - Setup

    func configure(with modelContext: ModelContext) {
        self.modelContext = modelContext

        // Check current authorization state without prompting
        isAuthorized = AlarmManager.shared.authorizationState == .authorized
        isNotificationAuthorized = false
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            Task { @MainActor in
                self.isNotificationAuthorized = settings.authorizationStatus == .authorized
            }
        }

        observeAuthorizationChanges()
        observeAlarmUpdates()

        // Sync alarms using the appropriate mechanism
        if isAuthorized {
            syncAllAlarms()
            scheduleAutoStopNotifications()
        } else {
            // Fallback: schedule via critical alert notifications
            syncAllFallbackAlarms()
        }

        updateNextAlarmDate()
    }

    /// Set up notification delegate to handle auto-stop notifications.
    private func setupNotificationHandling() {
        UNUserNotificationCenter.current().delegate = self

        // Register a silent category for auto-stop (no user-visible actions)
        let category = UNNotificationCategory(
            identifier: Self.autoStopCategoryID,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // MARK: - Authorization

    /// Request AlarmKit permission. Call contextually (e.g., when user creates first alarm), not at launch.
    func requestAuthorization() async {
        do {
            let state = try await AlarmManager.shared.requestAuthorization()
            isAuthorized = state == .authorized
            if isAuthorized {
                syncAllAlarms()
                scheduleAutoStopNotifications()
            }
        } catch {
            print("[AlarmKitService] Authorization error: \(error)")
            isAuthorized = false
        }
    }

    /// Request notification permission (for auto-stop and fallback alarms). Call contextually, not at launch.
    func requestNotificationAuthorization() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .timeSensitive])
            isNotificationAuthorized = granted
        } catch {
            print("[AlarmKitService] Notification authorization error: \(error)")
        }
    }

    private func observeAuthorizationChanges() {
        Task {
            for await authState in AlarmManager.shared.authorizationUpdates {
                let wasAuthorized = isAuthorized
                isAuthorized = authState == .authorized

                // Auto-migrate: user just granted AlarmKit in Settings
                if !wasAuthorized && isAuthorized {
                    migrateFromFallbackToAlarmKit()
                }
            }
        }
    }

    // MARK: - Alarm Observation

    private func observeAlarmUpdates() {
        Task {
            for await alarms in AlarmManager.shared.alarmUpdates {
                let previouslyAlerting = Set(activeAlarms.filter { $0.state == .alerting }.map(\.id))
                activeAlarms = alarms
                updateNextAlarmDate()

                // Foreground auto-stop: if app is alive when alarm fires, stop it after duration
                for alarm in alarms where alarm.state == .alerting && !previouslyAlerting.contains(alarm.id) {
                    scheduleInProcessAutoStop(for: alarm.id)
                }
            }
        }
    }

    // MARK: - Schedule / Cancel

    /// Schedule an AlarmKit alarm for the given SwiftData Alarm model.
    /// Returns the AlarmKit alarm ID so it can be stored on the model.
    @discardableResult
    func scheduleAlarm(for alarm: Alarm) async -> UUID? {
        guard isAuthorized else {
            print("[AlarmKitService] Not authorized — cannot schedule")
            return nil
        }

        // Cancel existing AlarmKit alarm if re-scheduling
        if let existingID = alarm.alarmKitID {
            try? AlarmManager.shared.cancel(id: existingID)
            removeAutoStopNotification(for: existingID)
        }

        let alarmKitID = UUID()

        // Build schedule
        let time = AlarmKit.Alarm.Schedule.Relative.Time(hour: alarm.hour, minute: alarm.minute)
        let recurrence: AlarmKit.Alarm.Schedule.Relative.Recurrence
        if alarm.repeatDays.isEmpty {
            recurrence = .never
        } else {
            recurrence = .weekly(alarm.repeatDays.compactMap { weekday(from: $0) })
        }
        let schedule = AlarmKit.Alarm.Schedule.relative(.init(time: time, repeats: recurrence))

        // Build presentation
        let snoozeButton = alarm.snoozeEnabled
            ? AlarmButton(text: "Snooze", textColor: .white, systemImageName: "zzz")
            : nil
        let stopButton = AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.fill")
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: alarm.label),
            stopButton: stopButton,
            secondaryButton: snoozeButton,
            secondaryButtonBehavior: alarm.snoozeEnabled ? .countdown : nil
        )
        let presentation = AlarmPresentation(alert: alert)

        // Build metadata
        let sound = AlarmSound.sound(named: alarm.soundName)
        let metadata = ShabbatAlarmMetadata(
            label: alarm.label,
            isShabbatAlarm: alarm.isShabbatAlarm,
            soundCategory: sound?.category.rawValue ?? "Shabbat Melodies"
        )

        // Build duration — postAlert handles snooze countdown only.
        // Auto-stop is handled by Layer 1 (local notification) + Layer 2 (in-process Task.sleep).
        // preAlert is NOT used for auto-stop — it's a pre-alarm countdown timer, not a ring duration limiter.
        let duration: AlarmKit.Alarm.CountdownDuration? = alarm.snoozeEnabled
            ? AlarmKit.Alarm.CountdownDuration(preAlert: nil, postAlert: TimeInterval(alarm.snoozeDurationSeconds))
            : nil

        // Build sound — use the custom alarm sound file from the bundle
        let alertSound: ActivityKit.AlertConfiguration.AlertSound
        if let sound {
            alertSound = .named("\(sound.fileName).\(sound.fileExtension)")
        } else {
            alertSound = .default
        }

        let config = AlarmManager.AlarmConfiguration(
            countdownDuration: duration,
            schedule: schedule,
            attributes: AlarmAttributes<ShabbatAlarmMetadata>(
                presentation: presentation,
                metadata: metadata,
                tintColor: .accentPurple
            ),
            stopIntent: StopAlarmIntent(alarmID: alarmKitID),
            sound: alertSound
        )

        do {
            _ = try await AlarmManager.shared.schedule(id: alarmKitID, configuration: config)

            // Schedule auto-stop notification at alarm fire time + duration
            scheduleAutoStopNotification(
                alarmKitID: alarmKitID,
                alarm: alarm
            )

            print("[AlarmKitService] Scheduled alarm: \(alarm.label) (id: \(alarmKitID))")
            return alarmKitID
        } catch {
            print("[AlarmKitService] Failed to schedule alarm: \(error)")
            return nil
        }
    }

    /// Cancel the AlarmKit alarm associated with a SwiftData Alarm model.
    func cancelAlarm(for alarm: Alarm) {
        guard let alarmKitID = alarm.alarmKitID else { return }
        do {
            try AlarmManager.shared.cancel(id: alarmKitID)
            removeAutoStopNotification(for: alarmKitID)
            print("[AlarmKitService] Cancelled alarm: \(alarm.label)")
        } catch {
            print("[AlarmKitService] Failed to cancel alarm: \(error)")
        }
    }

    /// Sync all enabled SwiftData alarms to AlarmKit.
    func syncAllAlarms() {
        guard let modelContext else { return }

        let descriptor = FetchDescriptor<Alarm>(
            predicate: #Predicate { $0.isEnabled }
        )

        do {
            let alarms = try modelContext.fetch(descriptor)
            Task {
                for alarm in alarms {
                    // Skip if already scheduled in AlarmKit (has a valid alarmKitID that's active)
                    if let existingID = alarm.alarmKitID,
                       activeAlarms.contains(where: { $0.id == existingID }) {
                        continue // Already scheduled, don't double-schedule
                    }
                    if let newID = await scheduleAlarm(for: alarm) {
                        alarm.alarmKitID = newID
                    }
                }
                try? modelContext.save()
                print("[AlarmKitService] Synced \(alarms.count) alarms to AlarmKit")
            }
        } catch {
            print("[AlarmKitService] Failed to fetch alarms for sync: \(error)")
        }
    }

    // MARK: - Next Alarm

    func updateNextAlarmDate() {
        guard let modelContext else {
            nextAlarmDate = nil
            sharedDefaults?.removeObject(forKey: "nextAlarmDate")
            return
        }

        let descriptor = FetchDescriptor<Alarm>(
            predicate: #Predicate { $0.isEnabled }
        )

        do {
            let alarms = try modelContext.fetch(descriptor)
            let now = Date()
            nextAlarmDate = alarms.compactMap { $0.nextFireDate(from: now) }.min()

            // Share with widget extension
            if let next = nextAlarmDate {
                sharedDefaults?.set(next, forKey: "nextAlarmDate")
            } else {
                sharedDefaults?.removeObject(forKey: "nextAlarmDate")
            }
        } catch {
            nextAlarmDate = nil
            sharedDefaults?.removeObject(forKey: "nextAlarmDate")
        }
    }

    // MARK: - Auto-Stop (Layered approach)
    //
    // Layer 1: UNNotification scheduled at (alarm fire time + duration).
    //          Works even if app is killed/suspended. iOS delivers the notification,
    //          wakes our app via the delegate, and we call AlarmManager.stop().
    //          This is the PRIMARY mechanism for Shabbat use.
    //
    // Layer 2: In-process Task.sleep when the app is alive (foreground/background).
    //          Provides immediate response without waiting for notification delivery.

    /// Layer 1: Schedule a local notification that fires at alarm time + auto-stop duration.
    /// When delivered, the delegate calls AlarmManager.stop().
    private func scheduleAutoStopNotification(alarmKitID: UUID, alarm: Alarm) {
        guard let fireDate = alarm.nextFireDate() else { return }

        let stopDate = fireDate.addingTimeInterval(TimeInterval(alarm.alarmDurationSeconds))
        let notificationID = Self.autoStopNotificationPrefix + alarmKitID.uuidString

        let content = UNMutableNotificationContent()
        content.categoryIdentifier = Self.autoStopCategoryID
        content.userInfo = [
            "alarmKitID": alarmKitID.uuidString,
            "action": "autoStop"
        ]
        // Silent notification — no sound, no banner (the alarm itself is the alert)
        content.sound = nil
        content.interruptionLevel = .passive

        let triggerDate = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: stopDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)

        let request = UNNotificationRequest(
            identifier: notificationID,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[AlarmKitService] Failed to schedule auto-stop notification: \(error)")
            } else {
                print("[AlarmKitService] Auto-stop notification scheduled for \(stopDate)")
            }
        }
    }

    /// Schedule auto-stop notifications for all enabled alarms.
    private func scheduleAutoStopNotifications() {
        guard let modelContext else { return }

        let descriptor = FetchDescriptor<Alarm>(
            predicate: #Predicate { $0.isEnabled }
        )

        guard let alarms = try? modelContext.fetch(descriptor) else { return }
        for alarm in alarms {
            if let alarmKitID = alarm.alarmKitID {
                scheduleAutoStopNotification(alarmKitID: alarmKitID, alarm: alarm)
            }
        }
    }

    /// Remove a pending auto-stop notification.
    private func removeAutoStopNotification(for alarmKitID: UUID) {
        let notificationID = Self.autoStopNotificationPrefix + alarmKitID.uuidString
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [notificationID]
        )
    }

    /// Layer 2: In-process auto-stop for when the app is alive.
    private func scheduleInProcessAutoStop(for alarmKitID: UUID) {
        guard let modelContext else { return }

        let descriptor = FetchDescriptor<Alarm>()
        guard let alarms = try? modelContext.fetch(descriptor),
              let alarm = alarms.first(where: { $0.alarmKitID == alarmKitID }) else {
            // Fallback: 30 seconds
            performDelayedStop(id: alarmKitID, after: 30)
            return
        }

        let duration = alarm.alarmDurationSeconds
        performDelayedStop(id: alarmKitID, after: duration)
        print("[AlarmKitService] In-process auto-stop scheduled for \(alarm.label) in \(duration)s")
    }

    private func performDelayedStop(id: UUID, after seconds: Int) {
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            if let current = activeAlarms.first(where: { $0.id == id }), current.state == .alerting {
                try? AlarmManager.shared.stop(id: id)
                print("[AlarmKitService] In-process auto-stopped alarm \(id)")
            }
        }
    }

    /// Called when an auto-stop notification is delivered (app may be in any state).
    func handleAutoStopNotification(alarmKitIDString: String) {
        guard let uuid = UUID(uuidString: alarmKitIDString) else { return }

        // Try to stop the alarm — it may have already been stopped by the user or Layer 2
        do {
            try AlarmManager.shared.stop(id: uuid)
            print("[AlarmKitService] Notification-triggered auto-stop for alarm \(uuid)")
        } catch {
            // Alarm may already be stopped — that's fine
            print("[AlarmKitService] Auto-stop notification: alarm \(uuid) already stopped or not found")
        }
    }

    // MARK: - Fallback Mode (Critical Alert Notifications)

    /// Schedule a fallback alarm using UNUserNotificationCenter with critical alert sound.
    /// Used when AlarmKit authorization is denied. Limited to 30s sound duration.
    func scheduleFallbackAlarm(for alarm: Alarm) {
        guard let fireDate = alarm.nextFireDate() else { return }

        let notificationID = Self.fallbackNotificationPrefix + alarm.id.uuidString

        // Remove any existing fallback notification for this alarm
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [notificationID]
        )

        let content = UNMutableNotificationContent()
        content.title = alarm.label
        content.body = String(localized: "Alarm")

        // Time-sensitive fallback (AlarmKit is the primary path)
        let sound = AlarmSound.sound(named: alarm.soundName)
        if let sound {
            content.sound = UNNotificationSound(
                named: UNNotificationSoundName("\(sound.fileName).\(sound.fileExtension)")
            )
        } else {
            content.sound = .default
        }
        content.interruptionLevel = .timeSensitive

        let triggerComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)

        let request = UNNotificationRequest(
            identifier: notificationID,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[AlarmKitService] Failed to schedule fallback alarm: \(error)")
            } else {
                print("[AlarmKitService] Fallback alarm scheduled for \(fireDate)")
            }
        }
    }

    /// Cancel a fallback notification for the given alarm.
    func cancelFallbackAlarm(for alarm: Alarm) {
        let notificationID = Self.fallbackNotificationPrefix + alarm.id.uuidString
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [notificationID]
        )
    }

    /// Schedule all enabled alarms as fallback notifications.
    private func syncAllFallbackAlarms() {
        guard let modelContext else { return }

        let descriptor = FetchDescriptor<Alarm>(
            predicate: #Predicate { $0.isEnabled }
        )

        guard let alarms = try? modelContext.fetch(descriptor) else { return }
        for alarm in alarms {
            scheduleFallbackAlarm(for: alarm)
        }
        print("[AlarmKitService] Synced \(alarms.count) alarms as fallback notifications")
    }

    // MARK: - Auto-Migration (Fallback → AlarmKit)

    /// Migrate all fallback alarms to AlarmKit after user grants permission.
    private func migrateFromFallbackToAlarmKit() {
        guard let modelContext else { return }

        let descriptor = FetchDescriptor<Alarm>(
            predicate: #Predicate { $0.isEnabled }
        )

        guard let alarms = try? modelContext.fetch(descriptor) else { return }

        // Remove all fallback notifications
        let fallbackIDs = alarms.map { Self.fallbackNotificationPrefix + $0.id.uuidString }
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: fallbackIDs
        )

        // Schedule via AlarmKit
        Task {
            for alarm in alarms {
                if let newID = await scheduleAlarm(for: alarm) {
                    alarm.alarmKitID = newID
                }
            }
            try? modelContext.save()
            scheduleAutoStopNotifications()
            print("[AlarmKitService] Migrated \(alarms.count) alarms from fallback to AlarmKit")
        }
    }

    // MARK: - Helpers

    /// Convert 0-based weekday index (0=Sunday) to Locale.Weekday.
    private func weekday(from index: Int) -> Locale.Weekday? {
        switch index {
        case 0: return .sunday
        case 1: return .monday
        case 2: return .tuesday
        case 3: return .wednesday
        case 4: return .thursday
        case 5: return .friday
        case 6: return .saturday
        default: return nil
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AlarmKitService: UNUserNotificationCenterDelegate {
    /// Called when notification arrives while app is in foreground — handle silently.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo

        if let action = userInfo["action"] as? String, action == "autoStop",
           let alarmKitIDString = userInfo["alarmKitID"] as? String {
            Task { @MainActor in
                AlarmKitService.shared.handleAutoStopNotification(alarmKitIDString: alarmKitIDString)
            }
            completionHandler([]) // Don't show anything — silent stop
        } else {
            completionHandler([.banner, .sound])
        }
    }

    /// Called when notification is delivered and app is in background/killed.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        if let action = userInfo["action"] as? String, action == "autoStop",
           let alarmKitIDString = userInfo["alarmKitID"] as? String {
            Task { @MainActor in
                AlarmKitService.shared.handleAutoStopNotification(alarmKitIDString: alarmKitIDString)
            }
        }

        completionHandler()
    }
}

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
                let currentlyAlerting = Set(alarms.filter { $0.state == .alerting }.map(\.id))
                activeAlarms = alarms
                updateNextAlarmDate()

                // Newly firing: arm auto-stop (both immediate UN + Task.sleep backup)
                for id in currentlyAlerting.subtracting(previouslyAlerting) {
                    armAutoStopOnFire(for: id)
                }

                // Finished alerting (user tapped Stop, or we stopped it): handle post-fire lifecycle
                for id in previouslyAlerting.subtracting(currentlyAlerting) {
                    handleAlarmFinishedAlerting(alarmKitID: id)
                }
            }
        }
    }

    // MARK: - Centralized Lifecycle
    //
    // All alarm mutations from views flow through enable/disable/delete.
    // Each method is idempotent and cleans up every side-effect tied to the alarm:
    // AlarmKit scheduling, auto-stop notifications, and fallback notifications.

    /// Turn an alarm on (or re-arm an already-on alarm after edits).
    /// Idempotent: cancels any prior AlarmKit alarm + notifications before scheduling fresh.
    /// Assigns the new AlarmKit ID to the model and saves.
    func enable(_ alarm: Alarm) async {
        // Clear any prior state — prior AlarmKit alarm, prior auto-stop, prior fallback.
        if let priorID = alarm.alarmKitID {
            try? AlarmManager.shared.cancel(id: priorID)
            removeAutoStopNotifications(for: priorID, repeatDays: alarm.repeatDays)
        }
        cancelFallbackAlarm(for: alarm)

        alarm.isEnabled = true

        if isAuthorized {
            if let newID = await scheduleAlarm(for: alarm) {
                alarm.alarmKitID = newID
            }
        } else {
            alarm.alarmKitID = nil
            scheduleFallbackAlarm(for: alarm)
        }

        try? alarm.modelContext?.save()
        updateNextAlarmDate()
    }

    /// Turn an alarm off without deleting the model.
    /// Idempotent: safe to call even if already disabled.
    func disable(_ alarm: Alarm) {
        if let id = alarm.alarmKitID {
            try? AlarmManager.shared.cancel(id: id)
            removeAutoStopNotifications(for: id, repeatDays: alarm.repeatDays)
            alarm.alarmKitID = nil
        }
        cancelFallbackAlarm(for: alarm)

        alarm.isEnabled = false
        try? alarm.modelContext?.save()
        updateNextAlarmDate()
    }

    /// Fully remove the alarm from the store and cancel all related notifications.
    func delete(_ alarm: Alarm) {
        let context = alarm.modelContext
        disable(alarm)
        context?.delete(alarm)
        try? context?.save()
        updateNextAlarmDate()
    }

    // MARK: - Schedule / Cancel (low-level)

    /// Schedule an AlarmKit alarm for the given SwiftData Alarm model.
    /// Returns the AlarmKit alarm ID so it can be stored on the model.
    /// Prefer `enable(_:)` from views — this is the low-level primitive.
    @discardableResult
    func scheduleAlarm(for alarm: Alarm) async -> UUID? {
        guard isAuthorized else {
            print("[AlarmKitService] Not authorized — cannot schedule")
            return nil
        }

        // Cancel existing AlarmKit alarm if re-scheduling
        if let existingID = alarm.alarmKitID {
            try? AlarmManager.shared.cancel(id: existingID)
            removeAutoStopNotifications(for: existingID, repeatDays: alarm.repeatDays)
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
            alertSound = .named("Sounds/\(sound.fileName).\(sound.fileExtension)")
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
            removeAutoStopNotifications(for: alarmKitID, repeatDays: alarm.repeatDays)
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
    /// For repeating alarms, schedules one recurring notification per repeat day.
    /// For one-time alarms, schedules a single non-repeating notification.
    private func scheduleAutoStopNotification(alarmKitID: UUID, alarm: Alarm) {
        // First remove any existing auto-stop notifications for this alarm
        removeAutoStopNotifications(for: alarmKitID, repeatDays: alarm.repeatDays)

        let center = UNUserNotificationCenter.current()
        let durationSeconds = alarm.alarmDurationSeconds

        // Build shared notification content
        func makeContent() -> UNMutableNotificationContent {
            let content = UNMutableNotificationContent()
            content.categoryIdentifier = Self.autoStopCategoryID
            content.userInfo = ["alarmKitID": alarmKitID.uuidString, "action": "autoStop"]
            content.title = alarm.label
            content.body = String(localized: "Alarm stopped automatically")
            content.sound = nil
            content.interruptionLevel = .timeSensitive
            return content
        }

        if alarm.repeatDays.isEmpty {
            // One-time alarm: schedule a single non-repeating notification at nextFireDate + duration
            guard let fireDate = alarm.nextFireDate() else { return }
            let stopDate = fireDate.addingTimeInterval(TimeInterval(durationSeconds))
            let triggerComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: stopDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
            let id = "\(Self.autoStopNotificationPrefix)\(alarmKitID.uuidString)-once"
            let request = UNNotificationRequest(identifier: id, content: makeContent(), trigger: trigger)
            center.add(request) { error in
                if let error { print("[AlarmKitService] Auto-stop (one-time) error: \(error)") }
            }
        } else {
            // Repeating alarm: schedule one recurring notification per repeat day
            // Each fires weekly on that weekday at alarmTime + durationSeconds
            for weekdayIndex in alarm.repeatDays {
                // weekdayIndex: 0=Sunday, 1=Monday, ..., 6=Saturday
                // UNCalendarNotificationTrigger weekday: 1=Sunday, 7=Saturday
                let unWeekday = weekdayIndex + 1

                // Calculate stop time: alarm hour:minute + duration seconds
                let totalSeconds = alarm.hour * 3600 + alarm.minute * 60 + durationSeconds
                let stopHour = (totalSeconds / 3600) % 24
                let stopMinute = (totalSeconds % 3600) / 60
                let stopSecond = totalSeconds % 60

                var triggerComponents = DateComponents()
                triggerComponents.weekday = unWeekday
                triggerComponents.hour = stopHour
                triggerComponents.minute = stopMinute
                triggerComponents.second = stopSecond

                let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: true)
                let id = "\(Self.autoStopNotificationPrefix)\(alarmKitID.uuidString)-\(weekdayIndex)"
                let request = UNNotificationRequest(identifier: id, content: makeContent(), trigger: trigger)
                center.add(request) { error in
                    if let error { print("[AlarmKitService] Auto-stop (day \(weekdayIndex)) error: \(error)") }
                }
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

    /// Remove all pending auto-stop notifications for an alarm (per-day + old-style migration).
    private func removeAutoStopNotifications(for alarmKitID: UUID, repeatDays: [Int]) {
        var ids: [String] = []
        if repeatDays.isEmpty {
            ids.append("\(Self.autoStopNotificationPrefix)\(alarmKitID.uuidString)-once")
        } else {
            for day in repeatDays {
                ids.append("\(Self.autoStopNotificationPrefix)\(alarmKitID.uuidString)-\(day)")
            }
        }
        // Also remove the old-style ID (migration safety for existing installs)
        ids.append(Self.autoStopNotificationPrefix + alarmKitID.uuidString)

        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// Called when an alarm enters the `.alerting` state.
    /// Arms both:
    ///   - a fresh UNNotification at now+duration (primary; survives suspension if the system
    ///     is willing to deliver it while our process is briefly alive during the fire)
    ///   - an in-process Task.sleep (backup; only works while app is alive)
        /// Layer 2 only: in-process Task.sleep backup when app is alive.
    /// Layer 1 (pre-scheduled timeSensitive notifications) handles the killed-app case.
    /// Note: Any alarm property change goes through enable(_:) which fully tears down
    /// and rebuilds all notifications — so pre-scheduled notifications are always in sync.
    private func armAutoStopOnFire(for alarmKitID: UUID) {
        guard let modelContext else {
            performDelayedStop(id: alarmKitID, after: 30)
            return
        }

        let descriptor = FetchDescriptor<Alarm>()
        guard let alarms = try? modelContext.fetch(descriptor),
              let alarm = alarms.first(where: { $0.alarmKitID == alarmKitID }) else {
            performDelayedStop(id: alarmKitID, after: 30)
            return
        }

        // Layer 2: in-process Task.sleep backup (pre-scheduled timeSensitive notifications are Layer 1)
        performDelayedStop(id: alarmKitID, after: alarm.alarmDurationSeconds)
        print("[AlarmKitService] Layer 2 auto-stop armed for \(alarm.label) in \(alarm.alarmDurationSeconds)s")
    }

    /// Called when an alarm transitions from `.alerting` back to idle (user tapped Stop,
    /// we auto-stopped it, or snooze countdown started). Handles:
    ///   - one-time alarms: flip isEnabled = false (mirrors stock Clock behavior)
    ///   - repeating alarms: re-arm the pre-scheduled auto-stop for the next occurrence
    private func handleAlarmFinishedAlerting(alarmKitID: UUID) {
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<Alarm>()
        guard let alarms = try? modelContext.fetch(descriptor),
              let alarm = alarms.first(where: { $0.alarmKitID == alarmKitID }) else { return }

        // Clear any pending auto-stop notifications (all day variants).
        removeAutoStopNotifications(for: alarmKitID, repeatDays: alarm.repeatDays)

        if alarm.repeatDays.isEmpty {
            // One-time alarm: AlarmKit itself removes the schedule. Mirror in our model.
            alarm.isEnabled = false
            alarm.alarmKitID = nil
            try? modelContext.save()
            updateNextAlarmDate()
        } else {
            // Repeating: re-arm pre-scheduled auto-stop for the next fire date.
            scheduleAutoStopNotification(alarmKitID: alarmKitID, alarm: alarm)
        }
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
            print("[AlarmKitService] Auto-stop: alarm \(uuid) already stopped or not found")
        }

        // Disable one-time alarms after firing (like iOS built-in clock)
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<Alarm>()
        guard let alarms = try? modelContext.fetch(descriptor),
              let alarm = alarms.first(where: { $0.alarmKitID == uuid }) else { return }

        if alarm.repeatDays.isEmpty {
            alarm.isEnabled = false
            alarm.alarmKitID = nil  // Clear so syncAllAlarms won't try to re-schedule it
            try? modelContext.save()
            print("[AlarmKitService] One-time alarm '\(alarm.label)' disabled after firing")
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
                named: UNNotificationSoundName("Sounds/\(sound.fileName).\(sound.fileExtension)")
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
            completionHandler([.banner]) // Show banner even in foreground so user sees alarm stopped
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

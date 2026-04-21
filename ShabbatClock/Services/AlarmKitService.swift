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

    /// True when BOTH AlarmKit AND notifications are denied — alarms cannot work at all.
    /// Distinct from isFallbackMode (AlarmKit denied but notifications available).
    var isBothDenied: Bool { !isAuthorized && !isNotificationAuthorized && hasBeenAskedForAuthorization }

    /// Whether the user has been prompted for AlarmKit authorization at least once.
    var hasBeenAskedForAuthorization: Bool {
        // If state is not .notDetermined, user has been asked
        AlarmManager.shared.authorizationState != .notDetermined
    }

    /// Maximum alarm duration in fallback mode (UNNotification sound limit).
    static let fallbackMaxDuration: Int = 30

    private var modelContext: ModelContext?
    private var modelContainer: ModelContainer?
    private var isConfigured = false

    /// Tracks alarm IDs currently being scheduled to prevent concurrent enable() calls
    /// from creating duplicate AlarmKit alarms for the same logical alarm.
    private var alarmsBeingScheduled: Set<UUID> = []

    /// Shared UserDefaults for widget communication.
    private let sharedDefaults = UserDefaults(suiteName: appGroupID)

    private override init() {
        super.init()
        setupNotificationHandling()
    }

    // MARK: - Setup

    /// Called early from App.init() to ensure background notification handlers
    /// can create a ModelContext even before configure() runs.
    func setContainer(_ container: ModelContainer) {
        self.modelContainer = container
    }

    func configure(with modelContext: ModelContext) {
        self.modelContext = modelContext
        self.modelContainer = modelContext.container

        // Guard against multiple configure() calls (onAppear can fire multiple times)
        guard !isConfigured else { return }
        isConfigured = true

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
            reconcileOrphanedAlarms()
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

    /// Re-check notification permission status without prompting.
    /// Call on foreground return so the UI reflects Settings changes.
    func refreshNotificationAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            Task { @MainActor in
                self.isNotificationAuthorized = settings.authorizationStatus == .authorized
            }
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

                // EXPERIMENT: Layer 2 (background task + Task.sleep) disabled to
                // isolate the silencer-alarm approach. Only the silencer detection
                // path below runs.
                for id in currentlyAlerting.subtracting(previouslyAlerting) {
                    handleNewlyAlertingAlarm(id: id)
                }

                // Finished alerting (user tapped Stop, or we stopped it): handle post-fire lifecycle
                for id in previouslyAlerting.subtracting(currentlyAlerting) {
                    handleAlarmFinishedAlerting(alarmKitID: id)
                }
            }
        }
    }

    /// Start a delayed stop wrapped in a UIApplication background task. The background
    /// task extends our runtime past the brief alarm-wake window, ensuring the delayed
    /// stop actually fires even when the phone is locked and the app was suspended.
    /// Handles an alarm transitioning to `.alerting` state.
    /// Only detects silencer alarms firing and cleans them up; no Layer 2 Task.sleep.
    private func handleNewlyAlertingAlarm(id alarmKitID: UUID) {
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<Alarm>()
        guard let alarms = try? modelContext.fetch(descriptor) else { return }

        // If this is a silencer alarm firing, try to cancel the main alarm
        // and clean up the silencer itself. Note: this only runs if our process
        // is alive when the silencer fires. The core experiment is whether the
        // silencer alarm SILENCES the main alarm at the system level regardless.
        if let mainAlarm = alarms.first(where: { $0.silencerAlarmKitID == alarmKitID }) {
            print("[AlarmKitService] 🤫 Silencer fired — cancelling main alarm '\(mainAlarm.label)'")
            if let mainID = mainAlarm.alarmKitID {
                try? AlarmManager.shared.stop(id: mainID)
                try? AlarmManager.shared.cancel(id: mainID)
            }
            try? AlarmManager.shared.stop(id: alarmKitID)
            try? AlarmManager.shared.cancel(id: alarmKitID)
            mainAlarm.silencerAlarmKitID = nil
            try? modelContext.save()
        }
    }

    // Layer 2 disabled for silencer-alarm isolation experiment.
    // When we want to re-enable, uncomment this and restore the call site above.
    private func armDelayedStopInBackgroundTask_DISABLED(for alarmKitID: UUID) {
        guard let modelContext else {
            print("[AlarmKitService] ⚠️ armDelayedStop: no modelContext")
            return
        }

        let descriptor = FetchDescriptor<Alarm>()
        guard let alarms = try? modelContext.fetch(descriptor) else {
            print("[AlarmKitService] ⚠️ armDelayedStop: fetch failed")
            return
        }

        // If this is a silencer alarm firing, stop the main alarm immediately
        // (this is the "silent alarm replaces ringing alarm" mechanism) and
        // then stop the silencer itself so its empty UI goes away quickly.
        if let mainAlarm = alarms.first(where: { $0.silencerAlarmKitID == alarmKitID }) {
            print("[AlarmKitService] 🤫 Silencer fired — cancelling main alarm '\(mainAlarm.label)'")
            if let mainID = mainAlarm.alarmKitID {
                try? AlarmManager.shared.stop(id: mainID)
                try? AlarmManager.shared.cancel(id: mainID)
            }
            // Stop the silencer's own ring (which is silent, but the UI/state still exists)
            try? AlarmManager.shared.stop(id: alarmKitID)
            try? AlarmManager.shared.cancel(id: alarmKitID)
            mainAlarm.silencerAlarmKitID = nil
            try? modelContext.save()
            return
        }

        guard let alarm = alarms.first(where: { $0.alarmKitID == alarmKitID }) else {
            print("[AlarmKitService] ⚠️ armDelayedStop: alarm not found for id=\(alarmKitID)")
            return
        }

        let durationSeconds = alarm.alarmDurationSeconds
        let label = alarm.label
        print("[AlarmKitService] 🔥 Alarm firing: '\(label)' — arming delayed stop in \(durationSeconds)s")

        // Begin a background task to extend our runtime past the alarm-wake window.
        // iOS grants ~30s of background runtime. For durations > 30s, the expiration
        // handler fires the stop as a fallback — better to stop early than never stop.
        var bgTaskID: UIBackgroundTaskIdentifier = .invalid
        let stopped = Atomic(false)

        bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "alarm-auto-stop-\(alarmKitID)") {
            // iOS is about to suspend us. Stop NOW rather than lose the ability to stop at all.
            if !stopped.swap(true) {
                print("[AlarmKitService] ⏱️ Background task expiring — stopping '\(label)' early")
                try? AlarmManager.shared.stop(id: alarmKitID)
                try? AlarmManager.shared.cancel(id: alarmKitID)
            }
            if bgTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(bgTaskID)
                bgTaskID = .invalid
            }
        }

        Task {
            try? await Task.sleep(for: .seconds(durationSeconds))

            if !stopped.swap(true) {
                do {
                    try AlarmManager.shared.stop(id: alarmKitID)
                    print("[AlarmKitService] ✅ Auto-stopped '\(label)' after \(durationSeconds)s")
                } catch {
                    print("[AlarmKitService] stop() failed for '\(label)': \(error)")
                }
                try? AlarmManager.shared.cancel(id: alarmKitID)
            }

            if bgTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(bgTaskID)
                bgTaskID = .invalid
            }
        }
    }

    /// Minimal thread-safe bool flag for the background-task race between timer and expiration.
    private final class Atomic<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var value: T
        init(_ initial: T) { self.value = initial }
        func swap(_ new: T) -> T {
            lock.lock(); defer { lock.unlock() }
            let old = value; value = new; return old
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
    /// Serialized per-alarm: if enable() is already in-flight for this alarm, the call is skipped.
    func enable(_ alarm: Alarm) async {
        // Prevent concurrent enable() calls for the same alarm (the await inside
        // scheduleAlarm yields, which can let a second enable() interleave and
        // create a duplicate AlarmKit alarm).
        guard !alarmsBeingScheduled.contains(alarm.id) else {
            print("[AlarmKitService] Skipping enable() for \(alarm.label) — already in-flight")
            return
        }
        alarmsBeingScheduled.insert(alarm.id)
        defer { alarmsBeingScheduled.remove(alarm.id) }

        // Clear any prior state — prior AlarmKit alarm, auto-stop alarm, notifications, fallback.
        if let priorID = alarm.alarmKitID {
            try? AlarmManager.shared.cancel(id: priorID)
            removeAutoStopNotifications(for: priorID, repeatDays: alarm.repeatDays)
        }
        cancelSilencerIfAny(for: alarm)
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
        cancelSilencerIfAny(for: alarm)
        cancelFallbackAlarm(for: alarm)

        alarm.isEnabled = false
        try? alarm.modelContext?.save()
        updateNextAlarmDate()
    }

    /// Fully remove the alarm from the store and cancel all related notifications.
    func delete(_ alarm: Alarm) {
        // Snapshot everything we need BEFORE deletion — once the model is removed
        // from the context, property access (e.g. repeatDays) crashes with a
        // "detached backing data" fault.
        let context = alarm.modelContext
        let alarmKitID = alarm.alarmKitID
        let silencerID = alarm.silencerAlarmKitID
        let repeatDays = alarm.repeatDays
        let alarmID = alarm.id

        // Cancel AlarmKit alarm + auto-stop notifications
        if let id = alarmKitID {
            try? AlarmManager.shared.cancel(id: id)
            removeAutoStopNotifications(for: id, repeatDays: repeatDays)
        }
        if let id = silencerID {
            try? AlarmManager.shared.cancel(id: id)
        }

        // Cancel fallback notification (inline — avoid touching the model)
        let fallbackID = Self.fallbackNotificationPrefix + alarmID.uuidString
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [fallbackID]
        )

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
        cancelSilencerIfAny(for: alarm)

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
        let isCustom = AlarmSound.isCustomSoundName(alarm.soundName)
        let sound = isCustom ? nil : AlarmSound.sound(named: alarm.soundName)
        let metadata = ShabbatAlarmMetadata(
            label: alarm.label,
            isShabbatAlarm: alarm.isShabbatAlarm,
            soundCategory: sound?.category.rawValue ?? (isCustom ? "Custom" : "Shabbat Melodies")
        )

        // Build duration — postAlert handles snooze countdown only.
        // Auto-stop is handled by Layer 1 (local notification) + Layer 2 (in-process Task.sleep).
        // preAlert is NOT used for auto-stop — it's a pre-alarm countdown timer, not a ring duration limiter.
        let duration: AlarmKit.Alarm.CountdownDuration? = alarm.snoozeEnabled
            ? AlarmKit.Alarm.CountdownDuration(preAlert: nil, postAlert: TimeInterval(alarm.snoozeDurationSeconds))
            : nil

        // Build sound — bundled sound uses "Sounds/..." prefix;
        // user-recorded sounds live in the App Group and use a bare filename.
        let alertSound: ActivityKit.AlertConfiguration.AlertSound
        if let customFileName = AlarmSound.customFileName(from: alarm.soundName),
           CustomSoundStore.fileExists(fileName: customFileName) {
            alertSound = .named(CustomSoundStore.alertSoundName(for: customFileName))
        } else if let sound {
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

            // EXPERIMENT: Layer 1 (UNNotification auto-stop) disabled to isolate
            // the silencer-alarm approach.
            // scheduleAutoStopNotification(alarmKitID: alarmKitID, alarm: alarm)

            // Schedule the silencer alarm as our primary auto-stop mechanism.
            // A second silent alarm fires at fireTime + duration, which causes iOS
            // to transition away from the first alarm's alerting state, silencing it.
            if let silencerID = await scheduleSilencerAlarm(for: alarm, mainAlarmHour: alarm.hour, mainAlarmMinute: alarm.minute) {
                alarm.silencerAlarmKitID = silencerID
            }

            print("[AlarmKitService] Scheduled alarm: \(alarm.label) (id: \(alarmKitID))")
            return alarmKitID
        } catch {
            print("[AlarmKitService] Failed to schedule alarm: \(error)")
            return nil
        }
    }

    /// Schedule a silent AlarmKit alarm at (mainAlarmFireDate + alarmDurationSeconds).
    /// When this fires, iOS transitions the system out of the main alarm's alerting
    /// state, effectively silencing the original alarm without needing our process
    /// to run code. Returns the silencer's AlarmKit ID so it can be cancelled.
    ///
    /// Uses `Schedule.fixed(Date)` for second-level precision. Non-repeating (.fixed
    /// is inherently one-time); for repeating alarms, the silencer is re-scheduled
    /// each time the main alarm fires via `handleNewlyAlertingAlarm`.
    private func scheduleSilencerAlarm(
        for alarm: Alarm,
        mainAlarmHour: Int,
        mainAlarmMinute: Int
    ) async -> UUID? {
        // Compute the main alarm's next fire date, then add the stop duration.
        guard let mainFireDate = alarm.nextFireDate() else {
            print("[AlarmKitService] ⚠️ Silencer: could not compute main fire date")
            return nil
        }
        let silencerFireDate = mainFireDate.addingTimeInterval(TimeInterval(alarm.alarmDurationSeconds))

        let silencerID = UUID()
        let schedule = AlarmKit.Alarm.Schedule.fixed(silencerFireDate)

        // Minimal presentation — the silencer should be invisible to the user.
        let stopButton = AlarmButton(text: " ", textColor: .clear, systemImageName: "stop.fill")
        let alert = AlarmPresentation.Alert(
            title: " ",
            stopButton: stopButton
        )
        let presentation = AlarmPresentation(alert: alert)

        let metadata = ShabbatAlarmMetadata(
            label: " ",
            isShabbatAlarm: false,
            soundCategory: "Silent"
        )

        let alertSound: ActivityKit.AlertConfiguration.AlertSound = .named("Sounds/Silent.m4a")

        let config = AlarmManager.AlarmConfiguration(
            countdownDuration: nil,
            schedule: schedule,
            attributes: AlarmAttributes<ShabbatAlarmMetadata>(
                presentation: presentation,
                metadata: metadata,
                tintColor: .clear
            ),
            stopIntent: StopAlarmIntent(alarmID: silencerID),
            sound: alertSound
        )

        do {
            _ = try await AlarmManager.shared.schedule(id: silencerID, configuration: config)
            let f = DateFormatter()
            f.dateFormat = "h:mm:ss a"
            print("[AlarmKitService] 🤫 Scheduled silencer at \(f.string(from: silencerFireDate)) (id: \(silencerID))")
            return silencerID
        } catch {
            print("[AlarmKitService] Failed to schedule silencer: \(error)")
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

    /// Cancel system-scheduled AlarmKit alarms and auto-stop notifications that no longer
    /// correspond to a SwiftData alarm. Guards against a crash/interruption between
    /// `AlarmManager.cancel` and `context.save()` in `delete()` leaving orphaned alarms
    /// that keep firing on their weekly recurrence forever.
    private func reconcileOrphanedAlarms() {
        guard let modelContext else { return }

        let systemAlarms: [AlarmKit.Alarm]
        do {
            systemAlarms = try AlarmManager.shared.alarms
        } catch {
            print("[AlarmKitService] Reconcile: failed to fetch system alarms: \(error)")
            return
        }

        let storedIDs: Set<UUID>
        do {
            let alarms = try modelContext.fetch(FetchDescriptor<Alarm>())
            storedIDs = Set(alarms.compactMap { $0.alarmKitID })
        } catch {
            print("[AlarmKitService] Reconcile: failed to fetch stored alarms: \(error)")
            return
        }

        let orphaned = systemAlarms.filter { !storedIDs.contains($0.id) }
        guard !orphaned.isEmpty else { return }

        for alarm in orphaned {
            try? AlarmManager.shared.cancel(id: alarm.id)
        }

        // Clear any lingering auto-stop notifications for the orphaned IDs.
        // We don't know each alarm's original repeatDays, so remove every possible key:
        // the one-time variant, all seven weekday variants, and the legacy bare-UUID form.
        let orphanIDStrings = orphaned.map { $0.id.uuidString }
        var notificationIDs: [String] = []
        for idString in orphanIDStrings {
            notificationIDs.append("\(Self.autoStopNotificationPrefix)\(idString)-once")
            for day in 0...6 {
                notificationIDs.append("\(Self.autoStopNotificationPrefix)\(idString)-\(day)")
            }
            notificationIDs.append(Self.autoStopNotificationPrefix + idString)
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: notificationIDs)

        print("[AlarmKitService] Reconcile: cancelled \(orphaned.count) orphaned alarm(s)")
    }

    /// Sync all enabled SwiftData alarms to AlarmKit.
    /// Only schedules alarms that don't already have an alarmKitID — avoids duplicates
    /// when activeAlarms hasn't been populated yet from the async alarmUpdates stream.
    func syncAllAlarms() {
        guard let modelContext else { return }

        let descriptor = FetchDescriptor<Alarm>(
            predicate: #Predicate { $0.isEnabled }
        )

        do {
            let alarms = try modelContext.fetch(descriptor)
            // Only schedule alarms that have no AlarmKit ID — they were never scheduled
            // or their ID was cleared (e.g., after a one-time alarm fired).
            // Alarms with an existing alarmKitID are already registered with AlarmKit.
            let unscheduled = alarms.filter { $0.alarmKitID == nil }
            guard !unscheduled.isEmpty else {
                print("[AlarmKitService] All \(alarms.count) alarms already scheduled")
                return
            }
            Task {
                for alarm in unscheduled {
                    if let newID = await scheduleAlarm(for: alarm) {
                        alarm.alarmKitID = newID
                    }
                }
                try? modelContext.save()
                print("[AlarmKitService] Synced \(unscheduled.count) new alarms to AlarmKit (\(alarms.count - unscheduled.count) already scheduled)")
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

    // MARK: - Auto-Stop
    //
    // A UNNotification scheduled at (alarm fire time + duration) is delivered when
    // the alarm's duration elapses. iOS wakes the app via the delegate, which calls
    // AlarmManager.stop(). Works even when the app is suspended or killed — critical
    // for Shabbat use where the app is backgrounded for hours.

    /// Schedule a local notification that fires at alarm time + auto-stop duration.
    /// When delivered, the delegate calls AlarmManager.stop().
    /// For repeating alarms, schedules one recurring notification per repeat day.
    /// For one-time alarms, schedules a single non-repeating notification.
    private func scheduleAutoStopNotification(alarmKitID: UUID, alarm: Alarm) {
        // First remove any existing auto-stop notifications for this alarm
        removeAutoStopNotifications(for: alarmKitID, repeatDays: alarm.repeatDays)

        let center = UNUserNotificationCenter.current()
        let durationSeconds = alarm.alarmDurationSeconds

        // Build shared notification content — shown as a banner informing the user
        // that the alarm auto-stopped. iOS requires visible content (title/body) for
        // reliable delivery and to wake the app's delegate when suspended.
        func makeContent() -> UNMutableNotificationContent {
            let content = UNMutableNotificationContent()
            content.userInfo = ["alarmKitID": alarmKitID.uuidString, "action": "autoStop"]
            content.title = String(localized: "Alarm Stopped")
            content.body = String(format: AppLanguage.localized("\"%@\" stopped automatically"), alarm.label)
            content.sound = nil
            content.interruptionLevel = .timeSensitive
            content.categoryIdentifier = Self.autoStopCategoryID
            return content
        }

        if alarm.repeatDays.isEmpty {
            // One-time alarm: schedule a single non-repeating notification at nextFireDate + duration
            guard let fireDate = alarm.nextFireDate() else {
                print("[AlarmKitService] ❌ Auto-stop: nextFireDate() returned nil for '\(alarm.label)' (isEnabled=\(alarm.isEnabled))")
                return
            }
            let stopDate = fireDate.addingTimeInterval(TimeInterval(durationSeconds))
            let triggerComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: stopDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
            let id = "\(Self.autoStopNotificationPrefix)\(alarmKitID.uuidString)-once"
            let request = UNNotificationRequest(identifier: id, content: makeContent(), trigger: trigger)
            print("[AlarmKitService] 🔔 Scheduling auto-stop '\(alarm.label)' fireDate=\(fireDate) stopDate=\(stopDate) duration=\(durationSeconds)s notifAuth=\(isNotificationAuthorized)")
            center.add(request) { error in
                if let error {
                    print("[AlarmKitService] ❌ Auto-stop (one-time) error: \(error)")
                } else {
                    print("[AlarmKitService] ✅ Auto-stop notification added: \(id)")
                }
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

        // User stopped the alarm (or we did) — silencer is no longer needed.
        cancelSilencerIfAny(for: alarm)

        if alarm.repeatDays.isEmpty {
            // One-time alarm: explicitly cancel in AlarmKit.
            try? AlarmManager.shared.cancel(id: alarmKitID)

            if alarm.zmanTypeRawValue != nil {
                // Zman alarm: delete entirely — user can recreate from ZmanimView.
                // Keeping a disabled zman alarm creates a confusing "ghost" bell.slash icon.
                modelContext.delete(alarm)
            } else {
                // Manual alarm: disable but keep (mirrors stock Clock behavior).
                alarm.isEnabled = false
                alarm.alarmKitID = nil
            }
            try? modelContext.save()
            updateNextAlarmDate()
        } else {
            // Repeating: re-arm pre-scheduled auto-stop for the next fire date.
            scheduleAutoStopNotification(alarmKitID: alarmKitID, alarm: alarm)
        }
    }

    /// Called when an auto-stop notification is delivered (app may be in any state).
    func handleAutoStopNotification(alarmKitIDString: String) {
        guard let uuid = UUID(uuidString: alarmKitIDString) else { return }

        // Diagnostic: check current state of the alarm in AlarmKit
        let systemAlarms = (try? AlarmManager.shared.alarms) ?? []
        let matching = systemAlarms.first(where: { $0.id == uuid })
        print("[AlarmKitService] 🔍 handleAutoStop: uuid=\(uuid) foundInSystem=\(matching != nil) state=\(String(describing: matching?.state)) totalSystemAlarms=\(systemAlarms.count)")

        // Stop the alarm's ringing. Call both stop() and cancel() defensively:
        // - stop() ends the alerting state (silences the sound)
        // - cancel() removes the alarm registration entirely
        // Some alarms require both to actually silence; stop() alone may leave
        // the system in an alerting state that keeps playing sound.
        do {
            try AlarmManager.shared.stop(id: uuid)
            print("[AlarmKitService] 🛑 stop() succeeded for alarm \(uuid)")
        } catch {
            print("[AlarmKitService] stop() failed for alarm \(uuid): \(error)")
        }
        do {
            try AlarmManager.shared.cancel(id: uuid)
            print("[AlarmKitService] 🛑 cancel() succeeded for alarm \(uuid)")
        } catch {
            print("[AlarmKitService] cancel() failed for alarm \(uuid): \(error)")
        }

        // Disable one-time alarms after firing (like iOS built-in clock)
        // Use existing context, or create a fresh one if app was launched in background
        // (before ContentView.onAppear had a chance to call configure())
        let context: ModelContext
        if let mc = modelContext {
            context = mc
        } else if let container = modelContainer {
            context = ModelContext(container)
            print("[AlarmKitService] Auto-stop: created fresh ModelContext (background launch)")
        } else {
            print("[AlarmKitService] Auto-stop: no ModelContext or ModelContainer available")
            return
        }

        let descriptor = FetchDescriptor<Alarm>()
        guard let alarms = try? context.fetch(descriptor),
              let alarm = alarms.first(where: { $0.alarmKitID == uuid }) else { return }

        if alarm.repeatDays.isEmpty {
            // Cancel the AlarmKit registration entirely (stop only stops alerting,
            // the alarm may still be registered in the system)
            try? AlarmManager.shared.cancel(id: uuid)
            removeAutoStopNotifications(for: uuid, repeatDays: alarm.repeatDays)

            if alarm.zmanTypeRawValue != nil {
                // Zman alarm: delete entirely to avoid ghost bell.slash icon
                context.delete(alarm)
            } else {
                // Manual alarm: disable but keep
                alarm.isEnabled = false
                alarm.alarmKitID = nil
            }
            try? context.save()
            print("[AlarmKitService] One-time alarm '\(alarm.label)' handled after firing")
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

        // Time-sensitive fallback (AlarmKit is the primary path).
        // Custom recordings live in the App Group and are referenced by bare filename;
        // bundled sounds use the "Sounds/" subdirectory.
        if let customFileName = AlarmSound.customFileName(from: alarm.soundName),
           CustomSoundStore.fileExists(fileName: customFileName) {
            content.sound = UNNotificationSound(
                named: UNNotificationSoundName(CustomSoundStore.alertSoundName(for: customFileName))
            )
        } else if let sound = AlarmSound.sound(named: alarm.soundName) {
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

    /// Cancel the silent "silencer" alarm previously scheduled alongside this alarm.
    /// Safe to call even if no silencer was scheduled.
    private func cancelSilencerIfAny(for alarm: Alarm) {
        if let silencerID = alarm.silencerAlarmKitID {
            try? AlarmManager.shared.cancel(id: silencerID)
            alarm.silencerAlarmKitID = nil
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
            print("[AlarmKitService] 📬 willPresent fired for auto-stop (foreground), alarmID=\(alarmKitIDString)")
            Task { @MainActor in
                AlarmKitService.shared.handleAutoStopNotification(alarmKitIDString: alarmKitIDString)
            }
            // Show the banner so the user knows the alarm auto-stopped.
            completionHandler([.banner])
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
            print("[AlarmKitService] 📬 didReceive fired for auto-stop (background/tap), alarmID=\(alarmKitIDString)")
            Task { @MainActor in
                AlarmKitService.shared.handleAutoStopNotification(alarmKitIDString: alarmKitIDString)
            }
        }

        completionHandler()
    }
}

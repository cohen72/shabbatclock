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
    /// Legacy prefix retained ONLY so we can flush leftover scheduled notifications
    /// from older app versions. The current silencer-alarm approach doesn't schedule these.
    static let autoStopNotificationPrefix = "autostop-"
    /// Legacy prefix retained ONLY so we can flush any fallback notifications scheduled by
    /// older app versions. We no longer schedule fallback notifications — if AlarmKit isn't
    /// authorized the app shows an in-app banner asking the user to enable it in Settings.
    static let fallbackNotificationPrefix = "fallback-"

    private(set) var isAuthorized: Bool = false
    private(set) var isNotificationAuthorized: Bool = false
    private(set) var activeAlarms: [AlarmKit.Alarm] = []
    private(set) var nextAlarmDate: Date?

    /// Whether the user has been prompted for AlarmKit authorization at least once.
    var hasBeenAskedForAuthorization: Bool {
        // If state is not .notDetermined, user has been asked
        AlarmManager.shared.authorizationState != .notDetermined
    }

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

        if isAuthorized {
            reconcileOrphanedAlarms()
            syncAllAlarms()
            // One-time cleanup: remove any auto-stop notifications scheduled by older
            // app versions that used the UNNotification-based auto-stop mechanism.
            flushAllAutoStopNotifications()
        }
        // One-time cleanup: flush any fallback notifications left by older versions
        // that used the UN-critical-alert fallback path (no longer supported).
        flushAllFallbackNotifications()

        updateNextAlarmDate()
    }

    /// Set up the notification delegate so the system can deliver our notifications.
    private func setupNotificationHandling() {
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - Authorization

    /// Request AlarmKit permission. Call contextually (e.g., when user creates first alarm), not at launch.
    func requestAuthorization() async {
        do {
            let state = try await AlarmManager.shared.requestAuthorization()
            isAuthorized = state == .authorized
            if isAuthorized {
                syncAllAlarms()
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

                // When user grants AlarmKit in Settings after previously denying,
                // re-schedule any enabled alarms that lost their AlarmKit registration.
                if !wasAuthorized && isAuthorized {
                    reconcileOrphanedAlarms()
                    syncAllAlarms()
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

                // Detect silencer alarms firing and clean them up (best-effort cancel
                // when our process happens to be alive at silencer fire time).
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

    /// Handles an alarm transitioning to `.alerting` state.
    /// When the silencer fires, we cancel it AS FAST AS POSSIBLE to minimize the
    /// window during which the haptic motor could vibrate. Order matters:
    /// 1. Cancel the silencer FIRST (stops its haptic ASAP)
    /// 2. Cancel the main alarm SECOND (it should already be silenced by the system
    ///    transitioning to the silencer, but we clean up to be safe)
    /// 3. SwiftData state cleanup happens last
    ///
    /// Wrapped in `beginBackgroundTask` as insurance: if iOS tries to re-suspend
    /// our process mid-cancellation (we were only woken briefly by alarmUpdates),
    /// the background task keeps us alive for the ~30s grace window, guaranteeing
    /// the cancels complete.
    private func handleNewlyAlertingAlarm(id alarmKitID: UUID) {
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<Alarm>()
        guard let alarms = try? modelContext.fetch(descriptor) else { return }

        guard let mainAlarm = alarms.first(where: { $0.silencerAlarmKitID == alarmKitID }) else {
            // Not a silencer — just a main alarm firing. Nothing to do here.
            return
        }

        // Snapshot before SwiftData mutations invalidate references
        let silencerID = alarmKitID
        let mainID = mainAlarm.alarmKitID
        let label = mainAlarm.label

        // Begin background task as insurance: if iOS tries to re-suspend us mid-cancel
        // (we were only briefly woken to receive the alarmUpdates event), this guarantees
        // the cancel work completes within the ~30s grace window.
        var bgTaskID: UIBackgroundTaskIdentifier = .invalid
        bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "silencer-cancel-\(silencerID)") {
            if bgTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(bgTaskID)
                bgTaskID = .invalid
            }
        }

        // Cancel silencer FIRST — this stops the haptic vibration ASAP
        try? AlarmManager.shared.cancel(id: silencerID)

        // Then clean up the main alarm registration
        if let mainID {
            try? AlarmManager.shared.cancel(id: mainID)
        }

        print("[AlarmKitService] 🤫 Silencer fired — cancelled main alarm '\(label)'")

        mainAlarm.silencerAlarmKitID = nil
        try? modelContext.save()

        if bgTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(bgTaskID)
            bgTaskID = .invalid
        }
    }

    // MARK: - Centralized Lifecycle
    //
    // All alarm mutations from views flow through enable/disable/delete.
    // Each method is idempotent and cleans up every side-effect tied to the alarm:
    // AlarmKit scheduling, silencer alarm, and fallback notifications.

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
            // AlarmKit not authorized — alarm row is saved but not scheduled.
            // The in-app banner prompts the user to enable AlarmKit in Settings.
            // Once they do, observeAuthorizationChanges triggers syncAllAlarms.
            alarm.alarmKitID = nil
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

        // One-time cleanup: remove any legacy fallback notification left by older builds.
        let legacyFallbackID = Self.fallbackNotificationPrefix + alarmID.uuidString
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [legacyFallbackID]
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
        // Auto-stop is handled by the silencer alarm (a separate silent AlarmKit alarm
        // scheduled at fireTime + alarmDurationSeconds — see scheduleSilencerAlarm).
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

            // Schedule the silent "silencer" alarm at fireTime + duration. When the
            // silencer fires, iOS transitions out of the main alarm's alerting state,
            // silencing it at the system level — without needing our process to run.
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

    // MARK: - Legacy Auto-Stop Notification Cleanup
    //
    // Older app versions scheduled UNNotifications at (alarm fire time + duration)
    // to call AlarmManager.stop() when delivered. The silencer-alarm approach has
    // replaced this entirely. These helpers remain ONLY to clean up leftover
    // notifications from older installs.

    /// One-time cleanup: flush any auto-stop notifications scheduled by older versions.
    /// The silencer-alarm approach replaced these; without flushing, leftover notifications
    /// from previous installs would still fire after their scheduled time.
    private func flushAllAutoStopNotifications() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let autoStopIDs = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(Self.autoStopNotificationPrefix) }
            if !autoStopIDs.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: autoStopIDs)
                print("[AlarmKitService] 🧹 Flushed \(autoStopIDs.count) legacy auto-stop notification(s)")
            }
        }
    }

    /// Remove any legacy auto-stop notifications for a specific alarm (cleanup helper
    /// for old installs; the silencer-alarm approach doesn't schedule these anymore).
    private func removeAutoStopNotifications(for alarmKitID: UUID, repeatDays: [Int]) {
        var ids: [String] = []
        if repeatDays.isEmpty {
            ids.append("\(Self.autoStopNotificationPrefix)\(alarmKitID.uuidString)-once")
        } else {
            for day in repeatDays {
                ids.append("\(Self.autoStopNotificationPrefix)\(alarmKitID.uuidString)-\(day)")
            }
        }
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
        }
        // Repeating alarms: silencer for the next occurrence is scheduled fresh
        // when the alarm is re-enabled or edited; nothing to do here.
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
    /// Default presentation for any notification arriving while app is in foreground.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Handles notification taps. Routes the Shabbat-reminder tap to the checklist UI
    /// via a NotificationCenter post that ContentView observes.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let action = userInfo["action"] as? String, action == "openShabbatChecklist" {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .openShabbatChecklist, object: nil)
            }
        }
        completionHandler()
    }
}

extension Notification.Name {
    /// Fired when the user taps the pre-Shabbat reminder notification.
    /// Observed by ContentView to present the Shabbat checklist sheet.
    static let openShabbatChecklist = Notification.Name("works.delicious.shabbatclock.openShabbatChecklist")
}

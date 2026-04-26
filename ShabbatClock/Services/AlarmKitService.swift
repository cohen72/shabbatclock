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

    private(set) var isAuthorized: Bool = false
    private(set) var isNotificationAuthorized: Bool = false
    /// True if the user explicitly denied AlarmKit. Drives post-denial UI
    /// (Open Settings link) in onboarding and in-app prompts.
    private(set) var isAlarmDenied: Bool = false
    /// True if the user explicitly denied notifications.
    private(set) var isNotificationDenied: Bool = false
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
        let alarmState = AlarmManager.shared.authorizationState
        isAuthorized = alarmState == .authorized
        isAlarmDenied = alarmState == .denied
        isNotificationAuthorized = false
        isNotificationDenied = false
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            Task { @MainActor in
                self.isNotificationAuthorized = settings.authorizationStatus == .authorized
                self.isNotificationDenied = settings.authorizationStatus == .denied
            }
        }

        observeAuthorizationChanges()
        observeAlarmUpdates()

        validateDefaultSoundPreference()

        if isAuthorized {
            reconcileOrphanedAlarms()
            syncAllAlarms()
        }

        updateNextAlarmDate()
    }

    /// Ensure `@AppStorage("defaultSound")` doesn't point at a missing custom recording.
    /// If the user previously picked a custom sound as the app default and the recording
    /// has since been deleted (or never migrated across App Group boundaries), reset the
    /// preference to the bundled default so newly-created alarms get a valid sound.
    private func validateDefaultSoundPreference() {
        let key = "defaultSound"
        let stored = UserDefaults.standard.string(forKey: key) ?? AlarmSound.defaultSound.name
        guard AlarmSound.isCustomSoundName(stored) else { return }
        guard let fileName = AlarmSound.customFileName(from: stored) else { return }
        if !CustomSoundStore.fileExists(fileName: fileName) {
            print("[AlarmKitService] Resetting defaultSound from stale custom '\(stored)' to bundled default")
            UserDefaults.standard.set(AlarmSound.defaultSound.name, forKey: key)
        }
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
            isAlarmDenied = state == .denied
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
                self.isNotificationDenied = settings.authorizationStatus == .denied
            }
        }
    }

    /// Re-check AlarmKit authorization status without prompting.
    /// Call on foreground return so the UI reflects the user toggling the permission
    /// in iOS Settings. `authorizationUpdates` is not reliable while the app is
    /// backgrounded, so this is the authoritative path after a Settings round-trip.
    func refreshAlarmAuthorization() {
        let state = AlarmManager.shared.authorizationState
        let wasAuthorized = isAuthorized
        isAuthorized = state == .authorized
        isAlarmDenied = state == .denied

        // If the user just granted permission, re-attach any existing alarms that
        // lost their AlarmKit registration while access was denied.
        if !wasAuthorized && isAuthorized {
            reconcileOrphanedAlarms()
            syncAllAlarms()
        }
    }

    /// Request notification permission (for auto-stop and fallback alarms). Call contextually, not at launch.
    func requestNotificationAuthorization() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .timeSensitive])
            isNotificationAuthorized = granted
            isNotificationDenied = !granted
        } catch {
            print("[AlarmKitService] Notification authorization error: \(error)")
        }
    }

    private func observeAuthorizationChanges() {
        Task {
            for await authState in AlarmManager.shared.authorizationUpdates {
                let wasAuthorized = isAuthorized
                isAuthorized = authState == .authorized
                isAlarmDenied = authState == .denied

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

        // Recurring alarms: the silencer is also recurring. Do NOT cancel — iOS
        // transitions the main alarm out of `.alerting` as a side effect of the
        // silencer firing, which is all we need. Both main and silencer stay
        // scheduled for next week.
        guard mainAlarm.repeatDays.isEmpty else {
            print("[AlarmKitService] 🤫 Silencer fired for recurring alarm '\(mainAlarm.label)' — leaving both scheduled")
            return
        }

        // Snapshot before SwiftData mutations invalidate references.
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

        // One-time alarm: cancel silencer FIRST (stops haptic ASAP), then main.
        try? AlarmManager.shared.cancel(id: silencerID)
        if let mainID {
            try? AlarmManager.shared.cancel(id: mainID)
        }

        print("[AlarmKitService] 🤫 Silencer fired — cancelled one-time alarm '\(label)'")

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

        // Clear any prior state — prior AlarmKit alarm and silencer alarm.
        if let priorID = alarm.alarmKitID {
            try? AlarmManager.shared.cancel(id: priorID)
        }
        cancelSilencerIfAny(for: alarm)

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

        if let id = alarmKitID {
            try? AlarmManager.shared.cancel(id: id)
        }
        if let id = silencerID {
            try? AlarmManager.shared.cancel(id: id)
        }

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
        }
        cancelSilencerIfAny(for: alarm)

        let alarmKitID = UUID()

        // Build schedule. One-time and recurring use different schedule types to match
        // the silencer's shape — the two alarms are a pair, so keeping their schedule
        // types symmetric avoids any risk of AlarmKit resolving them to different days.
        let schedule: AlarmKit.Alarm.Schedule
        if alarm.repeatDays.isEmpty {
            // One-time: pin to the absolute fire moment computed from today's wall-clock.
            // If `nextFireDate` can't be computed (shouldn't happen for an enabled alarm),
            // we can't schedule reliably.
            guard let mainFireDate = alarm.nextFireDate() else {
                print("[AlarmKitService] ⚠️ Could not compute fire date for one-time alarm '\(alarm.label)'")
                return nil
            }
            schedule = .fixed(mainFireDate)
        } else {
            let time = AlarmKit.Alarm.Schedule.Relative.Time(hour: alarm.hour, minute: alarm.minute)
            schedule = .relative(.init(
                time: time,
                repeats: .weekly(alarm.repeatDays.compactMap { weekday(from: $0) })
            ))
        }

        // Build presentation. Snooze is intentionally disabled app-wide for now — we
        // keep the model fields so we can re-enable easily later (e.g., weekday alarms).
        // Ignore `alarm.snoozeEnabled` here and always omit the secondary button.
        //
        // The Stop button text becomes "slide to <text>" when iOS renders it as a slider.
        // Using the alarm's label here ties the dismissal action to the specific event
        // ("slide to Shabbat Mincha") with a flame icon for warmth.
        let stopButton = AlarmButton(
            text: LocalizedStringResource(stringLiteral: alarm.label),
            textColor: .white,
            systemImageName: "flame.fill"
        )
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: alarm.label),
            stopButton: stopButton,
            secondaryButton: nil,
            secondaryButtonBehavior: nil
        )
        let presentation = AlarmPresentation(alert: alert)

        // Resolve the sound with a repair step: if the stored soundName references a
        // custom recording whose file is missing (e.g., recording was deleted, or the
        // @AppStorage("defaultSound") stuck on a stale custom reference), fall back
        // to the bundled default and rewrite the alarm's soundName so future edits
        // see a valid value.
        let storedIsCustom = AlarmSound.isCustomSoundName(alarm.soundName)
        let customFileMissing = storedIsCustom
            && (AlarmSound.customFileName(from: alarm.soundName).map { !CustomSoundStore.fileExists(fileName: $0) } ?? true)
        if customFileMissing {
            print("[AlarmKitService] ⚠️ Custom sound file missing for alarm '\(alarm.label)' — repairing to default sound")
            alarm.soundName = AlarmSound.defaultSound.name
        }

        let isCustom = AlarmSound.isCustomSoundName(alarm.soundName)
        let sound: AlarmSound? = {
            if isCustom { return nil }
            return AlarmSound.sound(named: alarm.soundName) ?? AlarmSound.defaultSound
        }()
        let metadata = ShabbatAlarmMetadata(
            label: alarm.label,
            isShabbatAlarm: alarm.isShabbatAlarm,
            soundCategory: sound?.category.rawValue ?? (isCustom ? "Custom" : "Shabbat Melodies")
        )

        // Build duration — AlarmKit's `postAlert` drives the snooze countdown; with
        // snooze disabled app-wide, we pass nil. Auto-stop is handled by the silencer
        // alarm (scheduled separately at fireTime + alarmDurationSeconds).
        let duration: AlarmKit.Alarm.CountdownDuration? = nil

        // Build sound — bundled sound uses "Sounds/..." prefix;
        // user-recorded sounds live in the App Group and use a bare filename.
        let alertSound: ActivityKit.AlertConfiguration.AlertSound
        if let customFileName = AlarmSound.customFileName(from: alarm.soundName),
           CustomSoundStore.fileExists(fileName: customFileName) {
            alertSound = .named(CustomSoundStore.alertSoundName(for: customFileName))
        } else if let sound {
            alertSound = .named("Sounds/\(sound.fileName).\(sound.fileExtension)")
        } else {
            // Should be unreachable with the sound-fallback above, but logged defensively
            // so we can investigate if it ever happens in production.
            print("[AlarmKitService] ⚠️ Falling back to default iOS alarm sound for alarm '\(alarm.label)' (soundName='\(alarm.soundName)')")
            alertSound = .default
        }

        // Schedule the silencer FIRST so we can bake its ID into the main alarm's
        // StopAlarmIntent. When the user slides Stop, iOS runs the intent directly
        // (even if our app is suspended) and the intent cancels both alarms — no
        // ghost silencer firing seconds later.
        let silencerID = await scheduleSilencerAlarm(for: alarm, mainAlarmHour: alarm.hour, mainAlarmMinute: alarm.minute)
        if silencerID == nil {
            // Main alarm will be scheduled below, but with no silencer → no auto-stop.
            // Logged loudly so we can diagnose if it ever happens.
            print("[AlarmKitService] 🚨 Alarm '\(alarm.label)' scheduled WITHOUT a silencer — will ring until manually stopped")
        }

        let config = AlarmManager.AlarmConfiguration(
            countdownDuration: duration,
            schedule: schedule,
            attributes: AlarmAttributes<ShabbatAlarmMetadata>(
                presentation: presentation,
                metadata: metadata,
                tintColor: .accentPurple
            ),
            stopIntent: StopAlarmIntent(alarmID: alarmKitID, silencerID: silencerID),
            sound: alertSound
        )

        do {
            _ = try await AlarmManager.shared.schedule(id: alarmKitID, configuration: config)
            if let silencerID {
                alarm.silencerAlarmKitID = silencerID
            }

            print("[AlarmKitService] Scheduled alarm: \(alarm.label) (id: \(alarmKitID))")
            return alarmKitID
        } catch {
            print("[AlarmKitService] Failed to schedule alarm: \(error)")
            return nil
        }
    }

    /// Schedule a silent AlarmKit alarm that fires `alarmDurationSeconds` after the main
    /// alarm's scheduled time. When this fires, iOS transitions the system out of the
    /// main alarm's alerting state, silencing the original alarm without needing our
    /// process to run code.
    ///
    /// Schedule strategy:
    /// - **One-time alarms** (`repeatDays.isEmpty`): use `.fixed(mainFireDate + duration)`.
    ///   This is the most reliable pairing — AlarmKit fires at that exact moment, and
    ///   there's no ambiguity around "next occurrence of this hour/minute" or midnight
    ///   rollover.
    /// - **Recurring alarms**: use `.relative(silencerHour:silencerMinute, weekly:[…])`
    ///   shifted forward by `duration/60` minutes, with weekdays rolled forward one day
    ///   when the silencer time crosses midnight. AlarmKit can't express sub-minute
    ///   offsets in `.relative`, so duration is rounded up to whole minutes (enforced
    ///   upstream by the UI's 60-second minimum).
    ///
    /// Returns the silencer's AlarmKit ID so the caller can store it for cancellation.
    private func scheduleSilencerAlarm(
        for alarm: Alarm,
        mainAlarmHour: Int,
        mainAlarmMinute: Int
    ) async -> UUID? {
        let schedule: AlarmKit.Alarm.Schedule
        if alarm.repeatDays.isEmpty {
            // One-time alarm: pin silencer to the main alarm's actual fire instant +
            // duration. This sidesteps every "next-occurrence" ambiguity (including
            // past-today and midnight rollover). If we can't compute the main alarm's
            // fire date, bail rather than schedule something wrong.
            guard let mainFireDate = alarm.nextFireDate() else {
                print("[AlarmKitService] ⚠️ Silencer: could not compute main fire date for one-time alarm '\(alarm.label)'")
                return nil
            }
            let silencerFireDate = mainFireDate.addingTimeInterval(TimeInterval(alarm.alarmDurationSeconds))
            schedule = .fixed(silencerFireDate)
        } else {
            // Recurring alarm: compute silencer hour/minute from main's hour/minute,
            // with midnight rollover rolling the weekdays forward by one.
            let durationMinutes = max(1, alarm.alarmDurationSeconds / 60)
            let totalMinutes = mainAlarmHour * 60 + mainAlarmMinute + durationMinutes
            let silencerHour = (totalMinutes / 60) % 24
            let silencerMinute = totalMinutes % 60
            let crossesMidnight = (totalMinutes / 60) >= 24
            let shiftedDays = crossesMidnight
                ? alarm.repeatDays.map { ($0 + 1) % 7 }
                : alarm.repeatDays
            let silencerTime = AlarmKit.Alarm.Schedule.Relative.Time(
                hour: silencerHour,
                minute: silencerMinute
            )
            schedule = .relative(.init(
                time: silencerTime,
                repeats: .weekly(shiftedDays.compactMap { weekday(from: $0) })
            ))
        }

        let silencerID = UUID()

        // Silencer presentation. The silencer plays a silent sound — it's not really
        // an alarm in the user-facing sense, it's a system-level mechanism for
        // dismissing the main alarm. But since iOS still surfaces it briefly when it
        // fires, we use the title to communicate "your alarm was auto-stopped" so the
        // user understands what they're seeing instead of a confusing blank alert.
        let stopButton = AlarmButton(
            text: "Got it",
            textColor: .white,
            systemImageName: "checkmark"
        )
        let alert = AlarmPresentation.Alert(
            title: "Alarm auto-stopped",
            stopButton: stopButton
        )
        let presentation = AlarmPresentation(alert: alert)

        let metadata = ShabbatAlarmMetadata(
            label: "Alarm auto-stopped",
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
                tintColor: .accentPurple
            ),
            stopIntent: StopAlarmIntent(alarmID: silencerID),
            sound: alertSound
        )

        do {
            _ = try await AlarmManager.shared.schedule(id: silencerID, configuration: config)
            print("[AlarmKitService] 🤫 Silencer scheduled for '\(alarm.label)' (duration: \(alarm.alarmDurationSeconds)s, id: \(silencerID))")
            return silencerID
        } catch {
            print("[AlarmKitService] ⚠️ Failed to schedule silencer for '\(alarm.label)' (duration: \(alarm.alarmDurationSeconds)s): \(error)")
            return nil
        }
    }

    /// Cancel the AlarmKit alarm associated with a SwiftData Alarm model.
    func cancelAlarm(for alarm: Alarm) {
        guard let alarmKitID = alarm.alarmKitID else { return }
        do {
            try AlarmManager.shared.cancel(id: alarmKitID)
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

    /// Called when an alarm transitions from `.alerting` back to idle (user tapped Stop,
    /// we auto-stopped it, or snooze countdown started). Handles:
    ///   - one-time alarms: flip isEnabled = false (mirrors stock Clock behavior)
    ///   - repeating alarms: re-arm the pre-scheduled auto-stop for the next occurrence
    private func handleAlarmFinishedAlerting(alarmKitID: UUID) {
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<Alarm>()
        guard let alarms = try? modelContext.fetch(descriptor),
              let alarm = alarms.first(where: { $0.alarmKitID == alarmKitID }) else { return }

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

    /// Cancel the silent "silencer" alarm previously scheduled alongside this alarm.
    /// Safe to call even if no silencer was scheduled.
    private func cancelSilencerIfAny(for alarm: Alarm) {
        if let silencerID = alarm.silencerAlarmKitID {
            try? AlarmManager.shared.cancel(id: silencerID)
            alarm.silencerAlarmKitID = nil
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

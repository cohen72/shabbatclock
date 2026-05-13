#if DEBUG
import SwiftUI
import SwiftData
import AlarmKit
import ActivityKit
import CoreLocation

/// Debug-only settings screen. Only visible in DEBUG builds.
/// Provides tools for testing permission prompts, alarm states, and other internals.
struct DebugView: View {
    @Environment(AlarmKitService.self) private var alarmService
    @Environment(\.modelContext) private var modelContext
    @StateObject private var locationManager = LocationManager.shared
    @ObservedObject private var storeManager = StoreManager.shared

    /// Live snapshot of every SwiftData Alarm row — used by the diagnostics section
    /// to cross-reference against what alarmsd actually has scheduled.
    @Query(sort: \Alarm.hour) private var storedAlarms: [Alarm]

    /// Manually-refreshed snapshot of `AlarmManager.shared.alarms`. Not live —
    /// the debug Refresh button repopulates it, plus on-appear.
    @State private var systemAlarmsSnapshot: [AlarmKit.Alarm] = []
    @State private var diagnosticsRefreshError: String?

    @State private var showingLocationPrompt = false
    @State private var showingAlarmPrompt = false
    @State private var showingNotificationPrompt = false
    @State private var showingOnboarding = false
    @State private var showingShabbatChecklist = false
    @State private var testAlarmStatus: String?
    @State private var showingNukeConfirmation = false
    @State private var nukeStatus: String?

    @Environment(\.dismiss) private var dismiss

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("debugSimulateFriday") private var simulateFriday = false
    @AppStorage("debug.composedSoundsOverride") private var composedSoundsOverride: String = ComposedSoundsDebugOverride.useRemote.rawValue

    var body: some View {
        ZStack {
            LinearGradient.nightSky
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Premium Override
                    premiumSection

                    // Simulate Friday
                    simulationSection

                    // Onboarding
                    onboardingSection

                    // Permission Prompts
                    permissionPromptsSection

                    // Permission States
                    permissionStatesSection

                    // AlarmKit State
                    alarmKitStateSection

                    // Alarm Diagnostics — system vs SwiftData cross-reference
                    alarmDiagnosticsSection

                    // Composed Sounds Override
                    composedSoundsSection

                    // Actions
                    actionsSection
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 120)
            }
        }
        .navigationTitle("Debug")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(role: .close) {
                    dismiss()
                }
            }
        }
        .fullScreenCover(isPresented: $showingLocationPrompt) {
            PermissionPromptView.location(
                onContinue: { showingLocationPrompt = false }
            )
            .applyLanguageOverride(AppLanguage.current)
        }
        .fullScreenCover(isPresented: $showingAlarmPrompt) {
            PermissionPromptView.alarms(
                onContinue: { showingAlarmPrompt = false }
            )
            .applyLanguageOverride(AppLanguage.current)
        }
        .fullScreenCover(isPresented: $showingNotificationPrompt) {
            PermissionPromptView.notifications(
                onContinue: { showingNotificationPrompt = false }
            )
            .applyLanguageOverride(AppLanguage.current)
        }
        .fullScreenCover(isPresented: $showingOnboarding) {
            OnboardingView {
                showingOnboarding = false
            }
            .applyLanguageOverride(AppLanguage.current)
        }
        .sheet(isPresented: $showingShabbatChecklist) {
            ShabbatChecklistView()
                .applyLanguageOverride(AppLanguage.current)
        }
        .alert("Cancel ALL AlarmKit alarms?", isPresented: $showingNukeConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Cancel All", role: .destructive) {
                let count = alarmService.cancelAllSystemAlarms()
                nukeStatus = "Cancelled \(count) system alarm(s)"
                refreshSystemAlarmsSnapshot()
            }
        } message: {
            Text("This cancels every AlarmKit alarm currently scheduled with iOS, including any orphans. SwiftData alarm rows remain but their alarmKitID/silencerAlarmKitID fields are cleared. Enabled alarms will re-schedule via the next sync.")
        }
        .onAppear {
            refreshSystemAlarmsSnapshot()
        }
    }

    // MARK: - Premium Override

    private var premiumSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Premium", icon: "crown.fill")

            VStack(spacing: 1) {
                HStack {
                    Text("Override Premium")
                        .font(.system(size: 13))
                        .foregroundStyle(.textPrimary)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { storeManager.debugPremiumOverride != nil },
                        set: { enabled in
                            storeManager.debugPremiumOverride = enabled ? false : nil
                            storeManager.syncAppStorage()
                        }
                    ))
                    .labelsHidden()
                    .tint(.goldAccent)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Color.surfaceCard)

                if storeManager.debugPremiumOverride != nil {
                    HStack {
                        Text("Premium State")
                            .font(.system(size: 13))
                            .foregroundStyle(.textPrimary)
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { storeManager.debugPremiumOverride ?? false },
                            set: { newValue in
                                storeManager.debugPremiumOverride = newValue
                                storeManager.syncAppStorage()
                            }
                        ))
                        .labelsHidden()
                        .tint(.goldAccent)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(Color.surfaceCard)
                }

                stateRow("Actual Subscriptions", value: storeManager.purchasedProductIDs.isEmpty ? "None" : "Active")
                stateRow("Effective isPremium", value: storeManager.isPremium ? "Yes" : "No")
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.surfaceBorder, lineWidth: 0.5)
            )
        }
    }

    // MARK: - Simulation

    private var simulationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Simulation", icon: "wand.and.stars")

            VStack(spacing: 1) {
                HStack {
                    Text("Simulate Friday")
                        .font(.system(size: 13))
                        .foregroundStyle(.textPrimary)
                    Spacer()
                    Toggle("", isOn: $simulateFriday)
                        .labelsHidden()
                        .tint(.goldAccent)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Color.surfaceCard)

                if simulateFriday {
                    stateRow("Effect", value: "Shabbat banners visible")
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.surfaceBorder, lineWidth: 0.5)
            )
        }
    }

    // MARK: - Onboarding

    private var onboardingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Onboarding", icon: "hand.wave.fill")

            VStack(spacing: 1) {
                debugButton("Preview Onboarding") {
                    showingOnboarding = true
                }
                debugButton("Reset Onboarding") {
                    hasCompletedOnboarding = false
                }
                debugButton("Preview Shabbat Checklist") {
                    showingShabbatChecklist = true
                }
                stateRow("Completed", value: hasCompletedOnboarding ? "Yes" : "No")
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.surfaceBorder, lineWidth: 0.5)
            )
        }
    }

    // MARK: - Permission Prompts Preview

    private var permissionPromptsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Permission Prompts", icon: "eye.fill")

            VStack(spacing: 1) {
                debugButton("Location Prompt") {
                    showingLocationPrompt = true
                }
                debugButton("Alarm Prompt") {
                    showingAlarmPrompt = true
                }
                debugButton("Notification Prompt") {
                    showingNotificationPrompt = true
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.surfaceBorder, lineWidth: 0.5)
            )
        }
    }

    // MARK: - Permission States

    private var permissionStatesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Permission States", icon: "lock.shield")

            VStack(spacing: 1) {
                stateRow("Location", value: locationManager.authorizationStatus.debugDescription)
                stateRow("AlarmKit", value: alarmService.isAuthorized ? "Authorized" : "Not Authorized")
                stateRow("Notifications", value: alarmService.isNotificationAuthorized ? "Authorized" : "Not Authorized")
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.surfaceBorder, lineWidth: 0.5)
            )
        }
    }

    // MARK: - AlarmKit State

    private var alarmKitStateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "AlarmKit", icon: "alarm.fill")

            VStack(spacing: 1) {
                stateRow("Authorized", value: alarmService.isAuthorized ? "Yes" : "No")
                stateRow("Observed alerting", value: "\(alarmService.activeAlarms.count)")
                stateRow("Next Alarm", value: alarmService.nextAlarmDate.map { dateString($0) } ?? "None")
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.surfaceBorder, lineWidth: 0.5)
            )
        }
    }

    // MARK: - Alarm Diagnostics (system vs SwiftData)

    /// Comprehensive cross-reference between what `alarmsd` thinks is scheduled
    /// (via `AlarmManager.shared.alarms`) and what our SwiftData layer believes.
    /// Mismatches here are the ground truth for zombie/orphan alarm hunting.
    private var alarmDiagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "Alarm Diagnostics", icon: "stethoscope")
                Spacer()
                Button {
                    refreshSystemAlarmsSnapshot()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.goldAccent)
                }
            }

            // System (alarmsd) section
            VStack(spacing: 1) {
                stateRow("System alarms (alarmsd)", value: "\(systemAlarmsSnapshot.count)")
                if let err = diagnosticsRefreshError {
                    stateRow("Refresh error", value: err)
                }
                if systemAlarmsSnapshot.isEmpty {
                    stateRow("(empty)", value: "—")
                } else {
                    ForEach(systemAlarmsSnapshot, id: \.id) { systemAlarm in
                        systemAlarmRow(systemAlarm)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.surfaceBorder, lineWidth: 0.5)
            )

            // SwiftData section
            VStack(spacing: 1) {
                stateRow("SwiftData alarms", value: "\(storedAlarms.count)")
                if storedAlarms.isEmpty {
                    stateRow("(empty)", value: "—")
                } else {
                    ForEach(storedAlarms, id: \.id) { alarm in
                        storedAlarmRow(alarm)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.surfaceBorder, lineWidth: 0.5)
            )

            // Nuclear cleanup
            VStack(spacing: 1) {
                debugButton("🔥 Cancel ALL system alarms") {
                    showingNukeConfirmation = true
                }
                if let status = nukeStatus {
                    stateRow("Last nuke", value: status)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.surfaceBorder, lineWidth: 0.5)
            )
        }
    }

    private func systemAlarmRow(_ systemAlarm: AlarmKit.Alarm) -> some View {
        let role = classifyRole(of: systemAlarm.id)
        let schedule = scheduleDescription(systemAlarm.schedule)
        let stateText = "\(systemAlarm.state)"
        let idShort = systemAlarm.id.uuidString.prefix(8)
        let valueText = "\(stateText) · \(schedule)"
        return stateRow("[\(role)] \(idShort)…", value: valueText)
    }

    private func storedAlarmRow(_ alarm: Alarm) -> some View {
        let mainID = alarm.alarmKitID.map { $0.uuidString.prefix(8) + "…" } ?? "nil"
        let silencerID = alarm.silencerAlarmKitID.map { $0.uuidString.prefix(8) + "…" } ?? "nil"
        let enabledMark = alarm.isEnabled ? "●" : "○"
        let label = "\(enabledMark) \(alarm.label) \(alarm.hour):\(String(format: "%02d", alarm.minute))"
        let value = "main=\(mainID) silencer=\(silencerID)"
        return stateRow(label, value: value)
    }

    /// Map a system-alarm UUID to a human-readable role:
    /// "MAIN: <label>" — found as `alarmKitID` on a SwiftData row
    /// "SILENCER: <label>" — found as `silencerAlarmKitID` on a SwiftData row
    /// "ORPHAN" — no SwiftData row references this UUID (zombie alarm — the bug class)
    private func classifyRole(of id: UUID) -> String {
        if let mainOwner = storedAlarms.first(where: { $0.alarmKitID == id }) {
            return "MAIN: \(mainOwner.label)"
        }
        if let silencerOwner = storedAlarms.first(where: { $0.silencerAlarmKitID == id }) {
            return "SILENCER: \(silencerOwner.label)"
        }
        return "⚠️ ORPHAN"
    }

    /// Human-readable summary of an AlarmKit schedule (fixed date or recurring weekly).
    private func scheduleDescription(_ schedule: AlarmKit.Alarm.Schedule?) -> String {
        guard let schedule else { return "no schedule" }
        switch schedule {
        case .fixed(let date):
            return "fixed \(dateString(date))"
        case .relative(let relative):
            let time = String(format: "%02d:%02d", relative.time.hour, relative.time.minute)
            switch relative.repeats {
            case .never:
                return "relative \(time) once"
            case .weekly(let days):
                let dayList = days.map { shortName(of: $0) }.joined(separator: ",")
                return "weekly \(time) [\(dayList)]"
            @unknown default:
                return "relative \(time) ?"
            }
        @unknown default:
            return "unknown schedule"
        }
    }

    private func shortName(of weekday: Locale.Weekday) -> String {
        switch weekday {
        case .sunday: return "Su"
        case .monday: return "Mo"
        case .tuesday: return "Tu"
        case .wednesday: return "We"
        case .thursday: return "Th"
        case .friday: return "Fr"
        case .saturday: return "Sa"
        @unknown default: return "?"
        }
    }

    private func refreshSystemAlarmsSnapshot() {
        do {
            systemAlarmsSnapshot = try AlarmManager.shared.alarms
            diagnosticsRefreshError = nil
        } catch {
            diagnosticsRefreshError = error.localizedDescription
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Actions", icon: "hammer.fill")

            VStack(spacing: 1) {
                debugButton("Test Zman Alarm (1 min)") {
                    createTestZmanAlarm()
                }
                debugButton("Test 60s Sound (rings in 20s)") {
                    scheduleLongSoundTest()
                }
                debugButton("Test 15min Sound (rings in 20s)") {
                    scheduleVeryLongSoundTest()
                }
                debugButton("Test 30min Sound (rings in 20s)") {
                    scheduleTest30MinSoundTest()
                }
                debugButton("Test Composer (rings in 20s, 30s audible)") {
                    scheduleComposedSoundTest()
                }
                if let status = testAlarmStatus {
                    stateRow("Test Alarm", value: status)
                }
                debugButton("Re-sync All Alarms") {
                    alarmService.syncAllAlarms()
                }
                debugButton("Request AlarmKit Auth") {
                    Task { await alarmService.requestAuthorization() }
                }
                debugButton("Request Notification Auth") {
                    Task { await alarmService.requestNotificationAuthorization() }
                }
                debugButton("Request Location") {
                    locationManager.requestPermission()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.surfaceBorder, lineWidth: 0.5)
            )
        }
    }

    // MARK: - Composed Sounds

    /// Local override for the `ff_use_composed_sounds` Remote Config flag. Lets us
    /// flip the composed-sounds path on/off in dev builds without touching Firebase.
    /// Production users never see this — DEBUG only.
    private var composedSoundsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Composed Sounds Flag", icon: "waveform.badge.plus")

            VStack(spacing: 1) {
                Picker("Override", selection: $composedSoundsOverride) {
                    Text("Use Remote").tag(ComposedSoundsDebugOverride.useRemote.rawValue)
                    Text("Force On").tag(ComposedSoundsDebugOverride.forceOn.rawValue)
                    Text("Force Off").tag(ComposedSoundsDebugOverride.forceOff.rawValue)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Color.surfaceCard)

                stateRow(
                    "Effective",
                    value: RemoteConfigService.shared.isComposedSoundsEnabled ? "ON" : "OFF"
                )
                stateRow(
                    "Remote value",
                    value: RemoteConfigService.shared.useComposedSoundsRemote ? "true" : "false"
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.surfaceBorder, lineWidth: 0.5)
            )
        }
    }

    /// Composes a sound on the fly (Lecha Dodi melody, 30-second audible portion + silence
    /// to 30 minutes total) and schedules an AlarmKit alarm 20 seconds out using the
    /// composed file. End-to-end smoke test for the composer + AlarmKit integration.
    ///
    /// What to listen for:
    /// - **First ~30s**: Lecha Dodi melody, fading out near the end
    /// - **After 30s**: silence — alarm UI keeps showing alerting until you tap Stop
    ///   or the system audio cap kicks in
    /// - **iOS default chime**: composition or file resolution failed; check console
    private func scheduleComposedSoundTest() {
        let lechaDodi = AlarmSound.defaultSound
        guard let sourceURL = Bundle.main.url(
            forResource: "Sounds/\(lechaDodi.fileName)",
            withExtension: lechaDodi.fileExtension
        ) else {
            testAlarmStatus = "Failed: source file not found in bundle"
            return
        }

        let cacheKey = "debug_\(lechaDodi.fileName)_30s"
        testAlarmStatus = "Composing…"

        Task {
            // Composition is CPU-bound; run off-main so the picker UI stays responsive.
            let composedURL = await Task.detached(priority: .userInitiated) {
                AlarmSoundComposer.compose(
                    sourceURL: sourceURL,
                    audibleDurationSeconds: 30,
                    cacheKey: cacheKey
                )
            }.value

            guard let composedURL else {
                testAlarmStatus = "Failed: composer returned nil"
                return
            }

            let fireDate = Date().addingTimeInterval(20)
            let schedule = AlarmKit.Alarm.Schedule.fixed(fireDate)

            let stopButton = AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.fill")
            let alert = AlarmPresentation.Alert(
                title: "Composer Test (30s audible)",
                stopButton: stopButton
            )
            let presentation = AlarmPresentation(alert: alert)

            let metadata = ShabbatAlarmMetadata(
                label: "Composer Test",
                isShabbatAlarm: false,
                soundCategory: "Test"
            )

            let alertSound: ActivityKit.AlertConfiguration.AlertSound = .named(composedURL.lastPathComponent)

            let id = UUID()
            let config = AlarmManager.AlarmConfiguration(
                countdownDuration: nil,
                schedule: schedule,
                attributes: AlarmAttributes<ShabbatAlarmMetadata>(
                    presentation: presentation,
                    metadata: metadata,
                    tintColor: .accentPurple
                ),
                stopIntent: StopAlarmIntent(alarmID: id),
                sound: alertSound
            )

            do {
                _ = try await AlarmManager.shared.schedule(id: id, configuration: config)
                let attrs = try? FileManager.default.attributesOfItem(atPath: composedURL.path)
                let size = (attrs?[.size] as? Int).map { "\($0 / 1024) KB" } ?? "?"
                testAlarmStatus = "Rings in 20s · composed file \(size) · \(composedURL.lastPathComponent)"
            } catch {
                testAlarmStatus = "Failed: \(error.localizedDescription)"
            }
        }
    }

    /// Schedules a raw AlarmKit alarm 20 seconds from now using TestTone60.m4a (a 60-second
    /// pulsing tone). Lets us verify on-device whether iOS actually plays a full-minute custom
    /// sound or enforces the documented 30-second notification-sound cap.
    ///
    /// Intentionally does NOT create a SwiftData Alarm row or a silencer — this is the minimal
    /// diagnostic: one fixed-schedule AlarmKit alarm, see what happens when it fires.
    private func scheduleLongSoundTest() {
        let fireDate = Date().addingTimeInterval(20)
        let schedule = AlarmKit.Alarm.Schedule.fixed(fireDate)

        let stopButton = AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.fill")
        let alert = AlarmPresentation.Alert(
            title: "Sound Duration Test",
            stopButton: stopButton
        )
        let presentation = AlarmPresentation(alert: alert)

        let metadata = ShabbatAlarmMetadata(
            label: "Sound Duration Test",
            isShabbatAlarm: false,
            soundCategory: "Test"
        )

        let alertSound: ActivityKit.AlertConfiguration.AlertSound = .named("Sounds/TestTone60.m4a")

        let id = UUID()
        let config = AlarmManager.AlarmConfiguration(
            countdownDuration: nil,
            schedule: schedule,
            attributes: AlarmAttributes<ShabbatAlarmMetadata>(
                presentation: presentation,
                metadata: metadata,
                tintColor: .accentPurple
            ),
            stopIntent: StopAlarmIntent(alarmID: id),
            sound: alertSound
        )

        Task {
            do {
                _ = try await AlarmManager.shared.schedule(id: id, configuration: config)
                testAlarmStatus = "Rings in 20s · TestTone60 (60s pulsing tone)"
            } catch {
                testAlarmStatus = "Failed: \(error.localizedDescription)"
            }
        }
    }

    /// Schedules a raw AlarmKit alarm 20 seconds from now using TestTone15min.m4a (a
    /// 15-minute pulsing tone). Tests whether iOS will play a custom alert sound longer
    /// than the documented 30-second cap, or whether it falls back to the iOS default.
    ///
    /// What to listen for:
    /// - **Plays full 15 min of pulsing**: 30s cap is not enforced for AlarmKit (great).
    ///   We could craft sounds that go silent before the alarm-state ends.
    /// - **Plays ~30s of pulsing then iOS default chime**: cap enforced as documented.
    /// - **Plays ~30s then silence (alarm UI stays up)**: cap enforced, file is truncated.
    /// - **iOS default chime from t=0**: file rejected outright before playback.
    private func scheduleVeryLongSoundTest() {
        let fireDate = Date().addingTimeInterval(20)
        let schedule = AlarmKit.Alarm.Schedule.fixed(fireDate)

        let stopButton = AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.fill")
        let alert = AlarmPresentation.Alert(
            title: "Sound Duration Test (15 min)",
            stopButton: stopButton
        )
        let presentation = AlarmPresentation(alert: alert)

        let metadata = ShabbatAlarmMetadata(
            label: "Sound Duration Test (15 min)",
            isShabbatAlarm: false,
            soundCategory: "Test"
        )

        let alertSound: ActivityKit.AlertConfiguration.AlertSound = .named("Sounds/TestTone15min.m4a")

        let id = UUID()
        let config = AlarmManager.AlarmConfiguration(
            countdownDuration: nil,
            schedule: schedule,
            attributes: AlarmAttributes<ShabbatAlarmMetadata>(
                presentation: presentation,
                metadata: metadata,
                tintColor: .accentPurple
            ),
            stopIntent: StopAlarmIntent(alarmID: id),
            sound: alertSound
        )

        Task {
            do {
                _ = try await AlarmManager.shared.schedule(id: id, configuration: config)
                testAlarmStatus = "Rings in 20s · TestTone15min (15-min pulsing tone)"
            } catch {
                testAlarmStatus = "Failed: \(error.localizedDescription)"
            }
        }
    }

    /// Schedules a raw AlarmKit alarm 20 seconds from now using test30Tone.m4a (a
    /// ~30-minute tone). Probes whether AlarmKit will play sound files longer than the
    /// 15-minute mark we observed previously, or whether the system imposes its own
    /// audio cap before the file ends.
    ///
    /// What to listen for:
    /// - **Plays well past 15 min**: file length is the limit, not a system cap.
    /// - **Audio stops at ~15 min, UI keeps alerting**: system audio cap, independent of file.
    /// - **Audio stops earlier (e.g. ~30s) then default/silence**: stricter cap than expected.
    private func scheduleTest30MinSoundTest() {
        let fireDate = Date().addingTimeInterval(20)
        let schedule = AlarmKit.Alarm.Schedule.fixed(fireDate)

        let stopButton = AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.fill")
        let alert = AlarmPresentation.Alert(
            title: "Sound Duration Test (30 min)",
            stopButton: stopButton
        )
        let presentation = AlarmPresentation(alert: alert)

        let metadata = ShabbatAlarmMetadata(
            label: "Sound Duration Test (30 min)",
            isShabbatAlarm: false,
            soundCategory: "Test"
        )

        let alertSound: ActivityKit.AlertConfiguration.AlertSound = .named("Sounds/test30Tone.m4a")

        let id = UUID()
        let config = AlarmManager.AlarmConfiguration(
            countdownDuration: nil,
            schedule: schedule,
            attributes: AlarmAttributes<ShabbatAlarmMetadata>(
                presentation: presentation,
                metadata: metadata,
                tintColor: .accentPurple
            ),
            stopIntent: StopAlarmIntent(alarmID: id),
            sound: alertSound
        )

        Task {
            do {
                _ = try await AlarmManager.shared.schedule(id: id, configuration: config)
                testAlarmStatus = "Rings in 20s · test30Tone (30-min tone)"
            } catch {
                testAlarmStatus = "Failed: \(error.localizedDescription)"
            }
        }
    }

    /// Creates a zman alarm that fires 1 minute from now with 60s auto-stop.
    /// Uses the same code path as ZmanAlarmSheet to test the full flow.
    private func createTestZmanAlarm() {
        let calendar = Calendar.current
        let fireDate = calendar.date(byAdding: .minute, value: 1, to: Date())!
        let hour = calendar.component(.hour, from: fireDate)
        let minute = calendar.component(.minute, from: fireDate)

        let alarm = Alarm()
        alarm.hour = hour
        alarm.minute = minute
        alarm.isEnabled = true
        alarm.label = "Test Zman"
        alarm.soundName = "Lecha Dodi"
        alarm.snoozeEnabled = false
        alarm.alarmDurationSeconds = 60
        alarm.zmanTypeRawValue = "netz"
        alarm.zmanMinutesBefore = 0

        modelContext.insert(alarm)

        Task {
            await alarmService.enable(alarm)
            let timeStr = String(format: "%d:%02d", hour, minute)
            testAlarmStatus = "Fires \(timeStr), 60s stop"
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func debugButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(.textPrimary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.forward")
                    .font(.system(size: 11))
                    .foregroundStyle(.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surfaceCard)
        }
    }

    @ViewBuilder
    private func stateRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.textPrimary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceCard)
    }

    private func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - CLAuthorizationStatus Debug Description

extension CLAuthorizationStatus {
    var debugDescription: String {
        switch self {
        case .notDetermined: return "Not Determined"
        case .restricted: return "Restricted"
        case .denied: return "Denied"
        case .authorizedAlways: return "Always"
        case .authorizedWhenInUse: return "When In Use"
        @unknown default: return "Unknown"
        }
    }
}
#endif

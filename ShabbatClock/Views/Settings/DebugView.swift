#if DEBUG
import SwiftUI
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

    @State private var showingLocationPrompt = false
    @State private var showingAlarmPrompt = false
    @State private var showingNotificationPrompt = false
    @State private var showingOnboarding = false
    @State private var showingShabbatChecklist = false
    @State private var testAlarmStatus: String?

    @Environment(\.dismiss) private var dismiss

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("debugSimulateFriday") private var simulateFriday = false

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
                stateRow("Active Alarms", value: "\(alarmService.activeAlarms.count)")
                stateRow("Next Alarm", value: alarmService.nextAlarmDate.map { dateString($0) } ?? "None")

                if !alarmService.activeAlarms.isEmpty {
                    ForEach(alarmService.activeAlarms, id: \.id) { alarm in
                        stateRow("  \(alarm.id.uuidString.prefix(8))...", value: "\(alarm.state)")
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.surfaceBorder, lineWidth: 0.5)
            )
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

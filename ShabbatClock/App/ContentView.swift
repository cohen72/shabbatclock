import SwiftUI
import SwiftData

/// Main content view with tab navigation.
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AlarmKitService.self) private var alarmService
    @EnvironmentObject private var remoteConfig: RemoteConfigService

    @AppStorage("appearanceMode") private var appearanceMode: String = AppearanceMode.system.rawValue
    @AppStorage("appLanguage") private var appLanguage: String = AppLanguage.system.rawValue
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("ambientMusicEnabled") private var ambientMusicEnabled = false
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedTab: Int = 0
    @State private var showingOnboarding = false
    @State private var showingShabbatChecklist = false

    private var resolvedColorScheme: ColorScheme? {
        AppearanceMode(rawValue: appearanceMode)?.colorScheme
    }

    private var resolvedLanguage: AppLanguage {
        // Ensure bundle override is applied before views resolve strings
        AppLanguage.applyBundleOverride()
        return AppLanguage(rawValue: appLanguage) ?? .system
    }

    init() {
        // Nav bar appearance intentionally not overridden — iOS 26 provides
        // automatic Liquid Glass blur that kicks in when content scrolls
        // under the bar, and remains transparent at the scroll edge. A global
        // `configureWithTransparentBackground()` swizzle defeats that blur and
        // lets ScrollView content flicker through the bar during tab-switch
        // snapshot transitions.

        let segmentFont = UIFont.systemFont(ofSize: 13, weight: .medium)
        UISegmentedControl.appearance().setTitleTextAttributes(
            [.font: segmentFont], for: .normal
        )
        UISegmentedControl.appearance().setTitleTextAttributes(
            [.font: segmentFont], for: .selected
        )
    }

    var body: some View {
        let zmanimTabEnabled = remoteConfig.isZmanimTabEnabled
        return TabView(selection: $selectedTab) {
            SwiftUI.Tab("Clock", systemImage: "clock.fill", value: 0) {
                MainClockView()
            }

            SwiftUI.Tab("Alarms", systemImage: "alarm.fill", value: 1) {
                AlarmListView()
            }

            if zmanimTabEnabled {
                SwiftUI.Tab("Zmanim", systemImage: "sun.horizon.fill", value: 2) {
                    ZmanimView()
                }
            }

            SwiftUI.Tab("Settings", systemImage: "gearshape.fill", value: 3) {
                SettingsView()
            }
        }
        .tint(.accentPurple)
        .preferredColorScheme(resolvedColorScheme)
        .applyLanguageOverride(resolvedLanguage)
        .id("lang-\(appLanguage)-zmanim-\(zmanimTabEnabled)") // Force full view rebuild when language or feature flags change
        .onAppear {
            alarmService.configure(with: modelContext)
            ZmanAlarmSyncService.shared.configure(with: modelContext)
            ShabbatReminderService.shared.reschedule()
            if !hasCompletedOnboarding {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    showingOnboarding = true
                }
            }
            // Set analytics super properties now that services are configured.
            // These attach to every subsequent event until they change.
            let alarmCount = (try? modelContext.fetch(FetchDescriptor<Alarm>()).count) ?? 0
            Analytics.setSuperProperties(
                isPremium: StoreManager.shared.isPremium,
                appLanguage: appLanguage,
                appearanceMode: appearanceMode,
                alarmCount: alarmCount,
                hasLocation: LocationManager.shared.isAuthorized || LocationManager.shared.isUsingManualLocation
            )
        }
        .onChange(of: selectedTab) { _, new in
            let tab: AnalyticsEvent.Tab
            switch new {
            case 0: tab = .clock
            case 1: tab = .alarms
            case 2: tab = .zmanim
            case 3: tab = .settings
            default: return
            }
            Analytics.track(.tabSwitched(tab: tab))
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                alarmService.refreshAlarmAuthorization()
                alarmService.refreshNotificationAuthorization()
                // Resume ambient music when returning to foreground (not during onboarding —
                // onboarding owns its own track via startBackgroundMusic there).
                if !showingOnboarding {
                    updateAmbientMusic()
                }
            } else if newPhase == .background {
                AudioManager.shared.stopBackgroundMusic(fadeOutDuration: 0.3)
            }
        }
        .onChange(of: ambientMusicEnabled) { _, _ in
            guard !showingOnboarding else { return }
            updateAmbientMusic()
        }
        .onChange(of: showingOnboarding) { _, isShowing in
            // When onboarding dismisses, kick off the main-app ambient track if the
            // user opted in (default is off). Before onboarding completes, the
            // onboarding screen owns the track.
            if !isShowing {
                updateAmbientMusic()
            }
        }
        .fullScreenCover(isPresented: $showingOnboarding) {
            OnboardingView {
                hasCompletedOnboarding = true
                showingOnboarding = false
            }
            .environment(alarmService)
            .applyLanguageOverride(resolvedLanguage)
        }
        .sheet(isPresented: $showingShabbatChecklist) {
            ShabbatChecklistView()
                .applyLanguageOverride(resolvedLanguage)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openShabbatChecklist)) { _ in
            showingShabbatChecklist = true
        }
    }

    /// Starts or stops ambient music based on the user's settings toggle.
    private func updateAmbientMusic() {
        if ambientMusicEnabled, let sound = AlarmSound.sound(byId: "shalom-aleichem") {
            AudioManager.shared.startBackgroundMusic(sound: sound)
        } else {
            AudioManager.shared.stopBackgroundMusic()
        }
    }
}

// MARK: - Language Override Modifier

extension View {
    @ViewBuilder
    func applyLanguageOverride(_ language: AppLanguage) -> some View {
        if let locale = language.locale, let direction = language.layoutDirection {
            self
                .environment(\.locale, locale)
                .environment(\.layoutDirection, direction)
        } else {
            self
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .modelContainer(for: Alarm.self, inMemory: true)
        .environment(AlarmKitService.shared)
}

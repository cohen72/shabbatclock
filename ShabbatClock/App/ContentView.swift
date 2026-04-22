import SwiftUI
import SwiftData

/// Main content view with tab navigation.
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AlarmKitService.self) private var alarmService

    @AppStorage("appearanceMode") private var appearanceMode: String = AppearanceMode.system.rawValue
    @AppStorage("appLanguage") private var appLanguage: String = AppLanguage.system.rawValue
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
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
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithTransparentBackground()
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance

        let segmentFont = UIFont.systemFont(ofSize: 13, weight: .medium)
        UISegmentedControl.appearance().setTitleTextAttributes(
            [.font: segmentFont], for: .normal
        )
        UISegmentedControl.appearance().setTitleTextAttributes(
            [.font: segmentFont], for: .selected
        )
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            SwiftUI.Tab("Clock", systemImage: "clock.fill", value: 0) {
                MainClockView()
            }

            SwiftUI.Tab("Alarms", systemImage: "alarm.fill", value: 1) {
                AlarmListView()
            }

            SwiftUI.Tab("Zmanim", systemImage: "sun.horizon.fill", value: 2) {
                ZmanimView()
            }

            SwiftUI.Tab("Settings", systemImage: "gearshape.fill", value: 3) {
                SettingsView()
            }
        }
        .tint(.accentPurple)
        .preferredColorScheme(resolvedColorScheme)
        .applyLanguageOverride(resolvedLanguage)
        .id("lang-\(appLanguage)") // Force full view rebuild when language changes
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
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                alarmService.refreshNotificationAuthorization()
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

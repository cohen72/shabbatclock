import SwiftUI
import SwiftData

/// Main content view with tab navigation.
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var alarmScheduler: AlarmScheduler

    @AppStorage("appearanceMode") private var appearanceMode: String = AppearanceMode.system.rawValue
    @AppStorage("appLanguage") private var appLanguage: String = AppLanguage.system.rawValue

    @State private var selectedTab: Int = 0

    private var resolvedColorScheme: ColorScheme? {
        AppearanceMode(rawValue: appearanceMode)?.colorScheme
    }

    private var resolvedLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguage) ?? .system
    }

    init() {
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithTransparentBackground()
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
    }

    var body: some View {
        ZStack {
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

            // Alarm firing overlay
            if alarmScheduler.isAlarmFiring {
                AlarmActiveView()
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
        .preferredColorScheme(resolvedColorScheme)
        .applyLanguageOverride(resolvedLanguage)
        .onAppear {
            alarmScheduler.configure(with: modelContext)
        }
        .animation(.easeInOut(duration: 0.3), value: alarmScheduler.isAlarmFiring)
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
        .environmentObject(AlarmScheduler.shared)
}

import SwiftUI
import SwiftData

/// Main content view with tab navigation.
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var alarmScheduler: AlarmScheduler

    @State private var selectedTab: Int = 0

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
            .toolbarBackgroundVisibility(.visible, for: .tabBar)
            .toolbarBackground(Color.black.opacity(0.8), for: .tabBar)

            // Alarm firing overlay
            if alarmScheduler.isAlarmFiring {
                AlarmActiveView()
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
        .onAppear {
            alarmScheduler.configure(with: modelContext)
        }
        .animation(.easeInOut(duration: 0.3), value: alarmScheduler.isAlarmFiring)
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .modelContainer(for: Alarm.self, inMemory: true)
        .environmentObject(AlarmScheduler.shared)
}

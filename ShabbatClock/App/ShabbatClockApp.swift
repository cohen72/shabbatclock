import SwiftUI
import SwiftData

@main
struct ShabbatClockApp: App {
    let container: ModelContainer
    @State private var alarmService = AlarmKitService.shared
    @StateObject private var storeManager = StoreManager.shared

    init() {
        // Apply language bundle override before any UI loads
        AppLanguage.applyBundleOverride()

        do {
            container = try ModelContainer(for: Alarm.self)
        } catch {
            fatalError("Failed to initialize ModelContainer: \(error)")
        }

        // Give AlarmKitService early access to the container so it can handle
        // background notifications even before ContentView.onAppear fires.
        AlarmKitService.shared.setContainer(container)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(alarmService)
                .environmentObject(storeManager)
        }
        .modelContainer(container)
    }
}

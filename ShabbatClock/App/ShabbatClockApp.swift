import SwiftUI
import SwiftData

@main
struct ShabbatClockApp: App {
    let container: ModelContainer
    @StateObject private var alarmScheduler = AlarmScheduler.shared

    init() {
        do {
            container = try ModelContainer(for: Alarm.self)
        } catch {
            fatalError("Failed to initialize ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(alarmScheduler)
        }
        .modelContainer(container)
    }
}

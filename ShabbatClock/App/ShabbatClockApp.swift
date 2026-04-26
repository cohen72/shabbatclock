import SwiftUI
import SwiftData
import FirebaseCore

@main
struct ShabbatClockApp: App {
  let container: ModelContainer
  @State private var alarmService = AlarmKitService.shared
  @StateObject private var storeManager = StoreManager.shared
  
  init() {

    FirebaseApp.configure()
    RemoteConfigService.shared.configure()
    // Apply language bundle override before any UI loads
    AppLanguage.applyBundleOverride()
    
    // Initialise Mixpanel before the first view loads so the app_opened event
    // fires with the correct super properties. Reads token from Secrets.plist;
    // no-ops if Secrets.plist is missing (e.g. fresh checkout without secrets).
    Analytics.configure()
    
    
    do {
      container = try ModelContainer(for: Alarm.self, CustomSound.self)
    } catch {
      fatalError("Failed to initialize ModelContainer: \(error)")
    }
    
    // Give AlarmKitService early access to the container so it can handle
    // background notifications even before ContentView.onAppear fires.
    AlarmKitService.shared.setContainer(container)
    
    Analytics.track(.appOpened)
  }
  
  var body: some Scene {
    WindowGroup {
      ContentView()
        .environment(alarmService)
        .environmentObject(storeManager)
        .environmentObject(RemoteConfigService.shared)
    }
    .modelContainer(container)
  }
}

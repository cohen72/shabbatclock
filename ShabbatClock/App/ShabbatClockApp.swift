import SwiftUI
import SwiftData
import FirebaseCore
import FirebaseAppCheck
import DeliciousKit
import DeliciousKitFirebase

/// Name of the secondary FirebaseApp instance used only for the shared
/// Delicious-apps newsletter backend's App Check verification. Kept separate
/// from the default FirebaseApp (ShabbatClock's own "shabbat-clock" project,
/// used for Analytics + Remote Config) since App Check tokens are scoped to
/// a specific Firebase project + app registration.
let deliciousAppsFirebaseAppName = "deliciousapps"

@main
struct ShabbatClockApp: App {
  let container: ModelContainer
  @State private var alarmService = AlarmKitService.shared
  @StateObject private var storeManager = StoreManager.shared
  @StateObject private var newsletterController = NewsletterController(
    app: "shabbatclock",
    attest: FirebaseAppCheckAttestProvider(appName: deliciousAppsFirebaseAppName)
  )

  init() {

    // Must be set before any FirebaseApp.configure() call.
    #if DEBUG
    AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
    #else
    AppCheck.setAppCheckProviderFactory(AppAttestCheckProviderFactory())
    #endif

    FirebaseApp.configure()

    // Secondary named app, purely for the shared newsletter backend's App
    // Check — does not touch ShabbatClock's own default Firebase project.
    if let path = Bundle.main.path(forResource: "GoogleService-Info-DeliciousApps", ofType: "plist"),
       let options = FirebaseOptions(contentsOfFile: path) {
      FirebaseApp.configure(name: deliciousAppsFirebaseAppName, options: options)
    } else {
      assertionFailure("GoogleService-Info-DeliciousApps.plist missing or invalid — newsletter signup will fail App Check verification.")
    }

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
        .environmentObject(newsletterController)
    }
    .modelContainer(container)
  }
}

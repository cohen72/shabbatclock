import Foundation
import FirebaseRemoteConfig

@MainActor
final class RemoteConfigService: ObservableObject {
    static let shared = RemoteConfigService()

    @Published private(set) var isZmanimTabEnabled: Bool = false
    @Published private(set) var freeAlarmLimit: Int = RemoteConfigService.freeAlarmLimitDefault

    fileprivate static let freeAlarmLimitDefault = 1
    fileprivate static let freeAlarmLimitRange = 1...10

    private let remoteConfig: RemoteConfig

    private init() {
        remoteConfig = RemoteConfig.remoteConfig()

        let settings = RemoteConfigSettings()
        #if DEBUG
        settings.minimumFetchInterval = 0
        #else
        settings.minimumFetchInterval = 3600
        #endif
        remoteConfig.configSettings = settings

        remoteConfig.setDefaults(fromPlist: "RemoteConfigDefaults")
        republishFlags()
    }

    func configure() {
        Task { await fetchAndActivate() }
        addRealtimeListener()
    }

    private func fetchAndActivate() async {
        do {
            _ = try await remoteConfig.fetchAndActivate()
            republishFlags()
        } catch {
            print("[RemoteConfig] fetch failed: \(error.localizedDescription) — using defaults")
        }
    }

    private func addRealtimeListener() {
        remoteConfig.addOnConfigUpdateListener { [weak self] _, error in
            guard error == nil else { return }
            self?.remoteConfig.activate { _, _ in
                Task { @MainActor in
                    self?.republishFlags()
                }
            }
        }
    }

    private func republishFlags() {
        isZmanimTabEnabled = remoteConfig[Flag.zmanimTab.rawValue].boolValue

        let raw = remoteConfig[Flag.freeAlarmLimit.rawValue].numberValue.intValue
        freeAlarmLimit = Self.freeAlarmLimitRange.contains(raw) ? raw : Self.freeAlarmLimitDefault
    }

    enum Flag: String {
        case zmanimTab = "ff_enable_zmanim_tab"
        case freeAlarmLimit = "free_alarm_limit"
    }
}

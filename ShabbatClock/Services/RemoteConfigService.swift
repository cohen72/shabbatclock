import Foundation
import FirebaseRemoteConfig

@MainActor
final class RemoteConfigService: ObservableObject {
    static let shared = RemoteConfigService()

    @Published private(set) var isZmanimTabEnabled: Bool = false
    @Published private(set) var freeAlarmLimit: Int = RemoteConfigService.freeAlarmLimitDefault
    @Published private(set) var useComposedSoundsRemote: Bool = false

    fileprivate static let freeAlarmLimitDefault = 1
    fileprivate static let freeAlarmLimitRange = 1...10

    /// Resolved flag: returns the debug override if set (DEBUG builds only),
    /// otherwise the value from Remote Config / defaults plist.
    var isComposedSoundsEnabled: Bool {
        #if DEBUG
        switch ComposedSoundsDebugOverride.current {
        case .forceOn: return true
        case .forceOff: return false
        case .useRemote: return useComposedSoundsRemote
        }
        #else
        return useComposedSoundsRemote
        #endif
    }

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
        useComposedSoundsRemote = remoteConfig[Flag.useComposedSounds.rawValue].boolValue

        let raw = remoteConfig[Flag.freeAlarmLimit.rawValue].numberValue.intValue
        freeAlarmLimit = Self.freeAlarmLimitRange.contains(raw) ? raw : Self.freeAlarmLimitDefault
    }

    enum Flag: String {
        case zmanimTab = "ff_enable_zmanim_tab"
        case useComposedSounds = "ff_use_composed_sounds"
        case freeAlarmLimit = "free_alarm_limit"
    }
}

#if DEBUG
/// Local override for the composed-sounds flag, used in DEBUG builds to test the
/// feature without round-tripping through Firebase Remote Config.
/// Persisted in `UserDefaults` so it survives relaunches during development.
enum ComposedSoundsDebugOverride: String {
    case useRemote
    case forceOn
    case forceOff

    private static let key = "debug.composedSoundsOverride"

    static var current: ComposedSoundsDebugOverride {
        get {
            let raw = UserDefaults.standard.string(forKey: key) ?? ""
            return ComposedSoundsDebugOverride(rawValue: raw) ?? .useRemote
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }
}
#endif

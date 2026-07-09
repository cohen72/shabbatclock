import Foundation
import DeliciousKit

/// Content shown in DeliciousKit's `WhatsNewView` on first launch after an
/// update. `version` is read from the bundle, not hand-typed, so the
/// per-version "seen" check always compares against what's actually
/// running — only `items` needs updating for each release.
extension WhatsNewConfig {
    static var current: WhatsNewConfig {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        return WhatsNewConfig(
            version: version,
            items: [
                WhatsNewItem(
                    systemImage: "envelope.fill",
                    title: String(localized: "Stay Updated"),
                    description: String(localized: "Sign in with Apple in Settings to get occasional product updates and offers by email.")
                ),
                WhatsNewItem(
                    systemImage: "globe",
                    title: String(localized: "More Accurate for Israel"),
                    description: String(localized: "The weekly Torah portion and Hebrew date now correctly follow Israel's calendar when you're there.")
                ),
            ]
        )
    }
}

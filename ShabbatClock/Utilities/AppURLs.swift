import Foundation

/// Single source of truth for all external URLs the app links to.
///
/// If ShabbatClock ever graduates to its own subdomain (e.g. shabbatclock.delicious.works),
/// update the `websiteRoot` below and every link in the app follows.
enum AppURLs {
    /// Root of the ShabbatClock marketing / legal site on delicious.works.
    /// Kept canonical under /shabbatclock so content is portable to a future subdomain.
    static let websiteRoot = "https://www.delicious.works/shabbatclock"

    static var privacyPolicy: URL { URL(string: "\(websiteRoot)/privacy")! }
    static var termsOfUse: URL { URL(string: "\(websiteRoot)/terms")! }
    static var support: URL { URL(string: "\(websiteRoot)/support")! }

    /// Support contact email — routes to the delicious.works studio inbox.
    static var supportMailto: URL { URL(string: "mailto:hello@delicious.works")! }

    /// Apple-provided URL for managing App Store subscriptions.
    static var manageSubscriptions: URL {
        URL(string: "https://apps.apple.com/account/subscriptions")!
    }
}

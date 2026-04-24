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

    /// Per-channel contact addresses — forwarded to the developer inbox via Namecheap email forwarding.
    private static let contactEmail = "shabbatclock-contact@delicious.works"
    private static let featureRequestEmail = "shabbatclock-feature@delicious.works"
    private static let bugReportEmail = "shabbatclock-bug@delicious.works"

    /// General contact address (kept for backward compatibility with any remaining call sites).
    static var supportMailto: URL { mailto(to: contactEmail, subject: "Shabbat Clock — Contact", body: diagnosticsFooter()) }

    /// Contact the developer with a general question.
    static var contactMailto: URL {
        mailto(to: contactEmail, subject: "Shabbat Clock — Contact", body: diagnosticsFooter())
    }

    /// Send a feature request to the developer.
    static var featureRequestMailto: URL {
        mailto(
            to: featureRequestEmail,
            subject: "Shabbat Clock — Feature Request",
            body: "Describe the feature you'd like to see:\n\n\n\n\(diagnosticsFooter())"
        )
    }

    /// Report a bug to the developer.
    static var bugReportMailto: URL {
        mailto(
            to: bugReportEmail,
            subject: "Shabbat Clock — Bug Report",
            body: "What happened:\n\n\nSteps to reproduce:\n\n\nExpected behavior:\n\n\n\(diagnosticsFooter())"
        )
    }

    /// Apple-provided URL for managing App Store subscriptions.
    static var manageSubscriptions: URL {
        URL(string: "https://apps.apple.com/account/subscriptions")!
    }

    private static func mailto(to address: String, subject: String, body: String) -> URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url!
    }

    private static func diagnosticsFooter() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        return "---\nVersion: \(version) (\(build))\niOS: \(os)"
    }
}

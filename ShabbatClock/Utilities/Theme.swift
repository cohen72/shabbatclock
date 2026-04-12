import SwiftUI

// MARK: - Appearance Setting

/// User's preferred appearance mode, persisted via @AppStorage("appearanceMode").
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: AppLanguage.localized("System")
        case .light: AppLanguage.localized("Light")
        case .dark: AppLanguage.localized("Dark")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

// MARK: - Language Setting

/// User's preferred app language, persisted via @AppStorage("appLanguage").
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case hebrew

    var id: String { rawValue }

    /// Display name shown in the picker.
    var displayName: String {
        switch self {
        case .system: AppLanguage.localized("System")
        case .english: "English"
        case .hebrew: "עברית"
        }
    }

    var locale: Locale? {
        switch self {
        case .system: nil
        case .english: Locale(identifier: "en")
        case .hebrew: Locale(identifier: "he")
        }
    }

    var layoutDirection: LayoutDirection? {
        switch self {
        case .system: nil
        case .english: .leftToRight
        case .hebrew: .rightToLeft
        }
    }

    /// The effective locale for this setting, falling back to the device locale for `.system`.
    var effectiveLocale: Locale {
        locale ?? Locale.current
    }

    /// Reads the current app language from UserDefaults (usable outside SwiftUI views).
    static var current: AppLanguage {
        let raw = UserDefaults.standard.string(forKey: "appLanguage") ?? "system"
        return AppLanguage(rawValue: raw) ?? .system
    }

    /// Looks up a localized string using the app's chosen language (not the device locale).
    /// Use this in non-SwiftUI code (services, models) where `.environment(\.locale)` isn't available.
    static func localized(_ key: String) -> String {
        let language = current
        // For system, use the default String(localized:) which respects device locale
        guard let locale = language.locale else {
            return String(localized: String.LocalizationValue(key))
        }
        // Find the .lproj bundle for the chosen language
        let langCode = locale.language.languageCode?.identifier ?? "en"
        if let path = Bundle.main.path(forResource: langCode, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle.localizedString(forKey: key, value: key, table: nil)
        }
        return String(localized: String.LocalizationValue(key))
    }

    /// Apply the language override to Bundle.main so that SwiftUI LocalizedStringKey
    /// and all bundle-based lookups use the correct language immediately.
    /// Call this when the language setting changes and on app launch.
    static func applyBundleOverride() {
        let language = current
        if let locale = language.locale {
            let langCode = locale.language.languageCode?.identifier ?? "en"
            OverriddenBundle.overriddenLanguage = langCode
            // Also set AppleLanguages for next launch
            UserDefaults.standard.set([langCode], forKey: "AppleLanguages")
        } else {
            OverriddenBundle.overriddenLanguage = nil
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
        // Swizzle Bundle.main if not already done
        OverriddenBundle.activate()
    }
}

// MARK: - Bundle Override for In-App Language Switching

/// Swizzles Bundle.main's localizedString(forKey:value:table:) to use the overridden language bundle.
/// This makes SwiftUI's LocalizedStringKey resolution respect the in-app language setting.
private class OverriddenBundle: Bundle, @unchecked Sendable {
    static var overriddenLanguage: String?
    private static var hasActivated = false

    static func activate() {
        guard !hasActivated else { return }
        hasActivated = true
        // Swizzle Bundle.main's class
        object_setClass(Bundle.main, OverriddenBundle.self)
    }

    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let lang = OverriddenBundle.overriddenLanguage,
           let path = Bundle.main.path(forResource: lang, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

// MARK: - Adaptive Color Definitions

/// All semantic colors adapt to the current color scheme automatically.
/// In dark mode: deep navy backgrounds, white text, gold/amber accents.
/// In light mode: warm cream/white backgrounds, dark text, same gold accents.
extension Color {
    // MARK: Backgrounds

    /// Primary background - deepest layer
    static let backgroundPrimary = Color(light: Color(hex: "F5F2EC"), dark: Color(hex: "141833"))

    /// Secondary background - slightly different shade for depth
    static let backgroundSecondary = Color(light: Color(hex: "EDE8DF"), dark: Color(hex: "08090F"))

    /// Card / elevated surface background
    static let surfaceCard = Color(light: Color(hex: "FAF8F5"), dark: Color.white.opacity(0.07))

    /// Card border
    static let surfaceBorder = Color(light: Color.black.opacity(0.07), dark: Color.white.opacity(0.1))

    /// Subtle surface fill (rows, inputs, etc.)
    static let surfaceSubtle = Color(light: Color.black.opacity(0.04), dark: Color.white.opacity(0.05))

    /// Selected/active surface — slightly darker than subtle for emphasis
    static let surfaceSelected = Color(light: Color.black.opacity(0.08), dark: Color.white.opacity(0.12))

    // MARK: Text

    /// Primary text color
    static let textPrimary = Color(light: Color(hex: "1A1A2E"), dark: .white)

    /// Secondary text color
    static let textSecondary = Color(light: Color(hex: "6B6B80"), dark: .white.opacity(0.7))

    // MARK: Accents (same in both modes)

    /// Main accent - the warm gold/amber
    static let accentPurple = Color(hex: "D4A548")

    /// Gold accent for highlights
    static let goldAccent = Color(hex: "F4A261")

    // MARK: Legacy / Compatibility

    static let primaryDark = Color(hex: "141833")
    static let secondaryDark = Color(hex: "08090F")
    static let starWhite = Color.white.opacity(0.9)
    static let tabBarBackground = Color(hex: "191739").opacity(0.95)
    static let cardBackground = Color(hex: "F0F0F0")

    // MARK: Clock-specific

    /// Clock face fill
    static let clockFaceFill = Color(light: Color.black.opacity(0.04), dark: Color.white.opacity(0.06))

    /// Clock face border
    static let clockFaceBorder = Color(light: Color.black.opacity(0.1), dark: Color.white.opacity(0.1))

    /// Clock hand color
    static let clockHand = Color(light: Color(hex: "1A1A2E"), dark: .white)

    /// Clock tick marks — cardinal (12, 3, 6, 9)
    static let clockTickCardinal = Color(light: Color.black.opacity(0.5), dark: Color.white.opacity(0.5))

    /// Clock tick marks — minor
    static let clockTickMinor = Color(light: Color.black.opacity(0.2), dark: Color.white.opacity(0.25))
}

// MARK: - Adaptive Color Initializer

extension Color {
    /// Creates a color that automatically adapts between light and dark mode.
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(dark)
                : UIColor(light)
        })
    }
}

// MARK: - Hex Color Initializer

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Adaptive Gradients

extension LinearGradient {
    /// Main app background gradient — adapts to color scheme.
    static let nightSky = LinearGradient(
        colors: [.backgroundPrimary, .backgroundSecondary],
        startPoint: .top,
        endPoint: .bottom
    )

    static let nightSkyReversed = LinearGradient(
        colors: [.backgroundSecondary, .backgroundPrimary],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - View Modifiers

struct GlassMorphicCard: ViewModifier {
    var cornerRadius: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .glassEffect(in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}

extension View {
    func glassMorphic(cornerRadius: CGFloat = 20, opacity: Double = 0.15) -> some View {
        modifier(GlassMorphicCard(cornerRadius: cornerRadius))
    }

    func lightCard(cornerRadius: CGFloat = 16) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.cardBackground)
        )
    }

    func settingsCard(cornerRadius: CGFloat = 14) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.surfaceCard)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.surfaceBorder, lineWidth: 0.5)
                )
        )
    }

    /// Standard card background used throughout the app.
    func themeCard(cornerRadius: CGFloat = 14) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.surfaceCard)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.surfaceBorder, lineWidth: 0.5)
                )
        )
    }
}

// MARK: - ShapeStyle Extensions for foregroundStyle

extension ShapeStyle where Self == Color {
    static var textPrimary: Color { .textPrimary }
    static var textSecondary: Color { .textSecondary }
    static var textDark: Color { Color(hex: "191739") }
    static var accentPurple: Color { .accentPurple }
    static var goldAccent: Color { .goldAccent }
    static var primaryDark: Color { .primaryDark }
    static var secondaryDark: Color { .secondaryDark }
}

// MARK: - Typography

struct AppFont {
    static func timeDisplay(_ size: CGFloat = 72) -> Font {
        .system(size: size, weight: .heavy, design: .default)
    }

    static func header(_ size: CGFloat = 24) -> Font {
        .system(size: size, weight: .bold, design: .default)
    }

    static func body(_ size: CGFloat = 17) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }

    static func caption(_ size: CGFloat = 14) -> Font {
        .system(size: size, weight: .medium, design: .default)
    }
}

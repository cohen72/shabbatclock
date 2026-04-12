import SwiftUI

// MARK: - Color Palette
extension Color {
    // Primary gradient colors
    static let primaryDark = Color(hex: "141833")
    static let secondaryDark = Color(hex: "08090F")

    // Accent colors
    static let accentPurple = Color(hex: "D4A548")
    static let goldAccent = Color(hex: "F4A261")
    static let starWhite = Color.white.opacity(0.9)

    // Card colors
    static let cardBackground = Color(hex: "F0F0F0")
    static let glassMorphic = Color.white.opacity(0.15)
    static let glassMorphicLight = Color.white.opacity(0.25)

    // Text colors
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.7)
    static let textDark = Color(hex: "191739")

    // Tab bar
    static let tabBarBackground = Color(hex: "191739").opacity(0.95)
}

// MARK: - Hex Color Initializer
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
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

// MARK: - Gradients
extension LinearGradient {
    static let nightSky = LinearGradient(
        colors: [.primaryDark, .secondaryDark],
        startPoint: .top,
        endPoint: .bottom
    )

    static let nightSkyReversed = LinearGradient(
        colors: [.secondaryDark, .primaryDark],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - View Modifiers
struct GlassMorphicCard: ViewModifier {
    var cornerRadius: CGFloat = 20
    var opacity: Double = 0.15

    func body(content: Content) -> some View {
        content
            .glassEffect(in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}

struct LightCard: ViewModifier {
    var cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.cardBackground)
            )
    }
}

extension View {
    func glassMorphic(cornerRadius: CGFloat = 20, opacity: Double = 0.15) -> some View {
        modifier(GlassMorphicCard(cornerRadius: cornerRadius, opacity: opacity))
    }

    func lightCard(cornerRadius: CGFloat = 16) -> some View {
        modifier(LightCard(cornerRadius: cornerRadius))
    }

    func settingsCard(cornerRadius: CGFloat = 14) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - ShapeStyle Extensions for foregroundStyle
extension ShapeStyle where Self == Color {
    static var textPrimary: Color { .white }
    static var textSecondary: Color { .white.opacity(0.7) }
    static var textDark: Color { Color(hex: "191739") }
    static var accentPurple: Color { Color(hex: "D4A548") }
    static var goldAccent: Color { Color(hex: "F4A261") }
    static var primaryDark: Color { Color(hex: "141833") }
    static var secondaryDark: Color { Color(hex: "08090F") }
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

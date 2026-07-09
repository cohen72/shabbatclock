//
//  ShabbatClockTokens.swift
//  Maps ShabbatClock's existing palette/type (Theme.swift, AppFont) onto
//  DeliciousKit's DesignTokens protocol, so DeliciousKit views (WhatsNewView,
//  PermissionStepView, etc.) render on-brand instead of falling back to
//  DeliciousKit's default SoftTokens. Injected once at the app root
//  (ShabbatClockApp) via `.environment(\.designTokens, ShabbatClockTokens())`
//  — same pattern Snowball uses for its own SnowballTokens.
//

import SwiftUI
import DeliciousKit

struct ShabbatClockTokens: DesignTokens {
    static let name = "shabbatclock"

    var background: Color { .backgroundPrimary }
    var surface: Color { .surfaceCard }
    var primary: Color { .textPrimary }
    var accent: Color { .goldAccent }
    var onBackground: Color { .textPrimary }
    var onSurface: Color { .textPrimary }
    var onPrimary: Color { .white }

    var cornerRadius: CGFloat { 16 }
    var cornerStyle: RoundedCornerStyle { .continuous }
    var borderWidth: CGFloat { 0.5 }
    var borderColor: Color { .surfaceBorder }

    var spacingUnit: CGFloat { 8 }

    var displayFont: Font { AppFont.header(32) }
    var headlineFont: Font { AppFont.header(20) }
    var bodyFont: Font { AppFont.body(15) }
    var captionFont: Font { AppFont.caption(13) }

    var entranceSpring: Animation { .spring(response: 0.35, dampingFraction: 0.85) }
    var pressSpring: Animation { .spring(response: 0.25, dampingFraction: 0.8) }
    var entranceOffset: CGFloat { 16 }
    var staggerDelay: TimeInterval { 0.04 }

    var cardShadow: Bool { true }
    var cardBorder: Bool { true }
    var cardMaterial: Bool { false }
}

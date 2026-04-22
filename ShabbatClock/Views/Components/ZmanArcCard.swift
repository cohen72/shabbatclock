import SwiftUI

/// Hero card for ZmanAlarmSheet: a sun-arc showing where this zman falls in the day.
/// Layout: arc on the left column, name + time stacked on the right.
struct ZmanArcCard: View {
    let zman: ZmanimService.Zman
    let zmanTimeString: String

    @State private var dotProgress: CGFloat = 0

    private var arcFraction: CGFloat {
        Self.arcFraction(for: zman.type)
    }

    var body: some View {
        HStack(spacing: 20) {
            // Left column: arc — larger (160×80) with internal padding so endpoints
            // don't press against the card edge.
            ArcWithDot(progress: dotProgress)
                .frame(width: 160, height: 80)
                .padding(.horizontal, 8)

            // Right column: name + time, centered vertically to match arc
            VStack(alignment: .leading, spacing: 4) {
                Text(zman.hebrewName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.goldAccent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(zman.englishName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.textSecondary)
                    .lineLimit(1)

                Text(zmanTimeString)
                    .font(.system(size: 30, weight: .regular))
                    .monospacedDigit()
                    .foregroundStyle(.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .themeCard(cornerRadius: 14)
        .onAppear {
            dotProgress = 0
            withAnimation(.easeInOut(duration: 1.2).delay(0.25)) {
                dotProgress = arcFraction
            }
        }
    }

    /// Maps each zman type to a fraction along the day arc.
    /// 0.0 = sunrise, 0.5 = solar noon, 1.0 = sunset.
    /// Pre-dawn: negative values. Post-sunset: > 1.
    /// Arc represents the full halachic day: Alot HaShachar (0.0) to Tzeis HaKochavim (1.0).
    /// Fractions derived from typical halachic-hour positions normalized over ~13.9-hour span
    /// (Alot at −1.2h before Netz, Tzeis at +0.7h after Shkia).
    static func arcFraction(for type: ZmanimService.ZmanType) -> CGFloat {
        switch type {
        case .alotHashachar:   return 0.00    // start of halachic day
        case .misheyakir:      return 0.04    // 36 min later
        case .netz:            return 0.09    // sunrise
        case .sofZmanShma:     return 0.30    // +3 halachic hours
        case .sofZmanTefila:   return 0.37    // +4 halachic hours
        case .chatzot:         return 0.52    // solar noon (+6 halachic hours)
        case .minchaGedola:    return 0.55    // +6.5 halachic hours
        case .minchaKetana:    return 0.77    // +9.5 halachic hours
        case .plagHamincha:    return 0.86    // +10.75 halachic hours
        case .shkia:           return 0.95    // sunset (+12 halachic hours)
        case .tzeitHakochavim: return 1.00    // +42 min after sunset
        }
    }
}

// MARK: - ArcWithDot

/// Renders the arc + glowing dot, with the dot animating along the curve as `progress` changes.
/// Uses a custom `Animatable` implementation so the dot traces the arc rather than taking a
/// straight-line shortcut between start and end points.
private struct ArcWithDot: View, Animatable {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ArcShape()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(hex: "8B9DC3").opacity(0.85),
                                Color.goldAccent,
                                Color(hex: "E07A5F").opacity(0.9)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )

                dotView
                    .position(Self.dotPosition(in: geo.size, fraction: progress))
            }
        }
    }

    private var dotView: some View {
        ZStack {
            Circle()
                .fill(Color.goldAccent.opacity(0.25))
                .frame(width: 20, height: 20)
                .blur(radius: 4)
            Circle()
                .fill(Color.goldAccent)
                .frame(width: 10, height: 10)
        }
    }

    /// Maps a fraction to a point on the elliptical arc. Fractions are clamped to [0, 1]
    /// so pre-dawn and post-sunset zmanim still land on the arc endpoints (the text
    /// conveys the specific zman; the arc just shows approximate position-in-day).
    static func dotPosition(in size: CGSize, fraction: CGFloat) -> CGPoint {
        let clamped = max(0, min(1, fraction))
        let rx = size.width / 2
        let ry = size.height
        let t = CGFloat.pi + .pi * clamped
        let x = rx + rx * cos(t)
        let y = size.height + ry * sin(t)
        return CGPoint(x: x, y: y)
    }
}

/// An elliptical arc from bottom-left to bottom-right, peaking at the top center.
private struct ArcShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let rx = rect.width / 2
        let ry = rect.height
        let steps = 60
        for i in 0...steps {
            let t = CGFloat.pi + .pi * CGFloat(i) / CGFloat(steps)
            let x = rect.midX + rx * cos(t)
            let y = rect.maxY + ry * sin(t)
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }
}

// MARK: - Preview

#Preview("Sunrise") {
    ZStack {
        LinearGradient.nightSky.ignoresSafeArea()
        ZmanArcCard(
            zman: ZmanimService.Zman(
                type: .netz,
                time: Date(),
                hebrewName: "הנץ החמה",
                englishName: "Sunrise",
                description: ""
            ),
            zmanTimeString: "6:02 AM"
        )
        .padding()
    }
}

#Preview("Chatzot") {
    ZStack {
        LinearGradient.nightSky.ignoresSafeArea()
        ZmanArcCard(
            zman: ZmanimService.Zman(
                type: .chatzot,
                time: Date(),
                hebrewName: "חצות",
                englishName: "Midday",
                description: ""
            ),
            zmanTimeString: "12:39 PM"
        )
        .padding()
    }
}

#Preview("Alot HaShachar") {
    ZStack {
        LinearGradient.nightSky.ignoresSafeArea()
        ZmanArcCard(
            zman: ZmanimService.Zman(
                type: .alotHashachar,
                time: Date(),
                hebrewName: "עלות השחר",
                englishName: "Dawn",
                description: ""
            ),
            zmanTimeString: "4:50 AM"
        )
        .padding()
    }
}

import SwiftUI

/// Full-width week arc for the main dashboard.
/// Arc spans one week (havdalah → next havdalah). Two fixed markers show the upcoming
/// candle-lighting and havdalah times. A sun-dot animates from the left endpoint to
/// the user's current position in the week on appear.
///
/// Height is derived from width so the arc is always a true semicircle.
struct ShabbatWeekArcCard: View {
    let now: Date
    let candleLighting: Date?
    let havdalah: Date?

    @State private var dotProgress: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let arcHeight = width / 2

            ZStack(alignment: .top) {
                WeekArcShape()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(hex: "8B9DC3").opacity(0.55),
                                Color.goldAccent.opacity(0.85),
                                Color(hex: "E07A5F").opacity(0.55)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .frame(width: width, height: arcHeight)

                // Shabbat markers (fixed positions)
                if let candleFraction {
                    ShabbatMarker(symbol: "flame.fill", color: .goldAccent)
                        .position(
                            ArcMath.point(in: CGSize(width: width, height: arcHeight),
                                          fraction: candleFraction)
                        )
                }

                if let havdalahFraction {
                    ShabbatMarker(symbol: "moon.stars.fill", color: Color(hex: "8B9DC3"))
                        .position(
                            ArcMath.point(in: CGSize(width: width, height: arcHeight),
                                          fraction: havdalahFraction)
                        )
                }

                // Animated "now" sun-dot
                SunDot()
                    .position(
                        ArcMath.point(in: CGSize(width: width, height: arcHeight),
                                      fraction: dotProgress)
                    )
            }
            .frame(width: width, height: arcHeight)
        }
        .aspectRatio(2, contentMode: .fit)
        .padding(.top, 12) // breathing room above the arc peak for the dot glow
        .onAppear { animateIn() }
        .onChange(of: nowFraction) { _, _ in animateIn() }
    }

    // MARK: - Fractions

    /// Where "now" falls in the current week (havdalah → next havdalah cycle).
    /// Falls back to 0 if we don't have havdalah/candle data yet.
    private var nowFraction: CGFloat {
        guard let weekStart = weekStartHavdalah, let weekEnd = nextWeekHavdalah else {
            return 0
        }
        let total = weekEnd.timeIntervalSince(weekStart)
        guard total > 0 else { return 0 }
        let elapsed = now.timeIntervalSince(weekStart)
        return CGFloat(max(0, min(1, elapsed / total)))
    }

    private var candleFraction: CGFloat? {
        guard let candleLighting,
              let weekStart = weekStartHavdalah,
              let weekEnd = nextWeekHavdalah else { return nil }
        let total = weekEnd.timeIntervalSince(weekStart)
        guard total > 0 else { return nil }
        let elapsed = candleLighting.timeIntervalSince(weekStart)
        let f = elapsed / total
        guard f >= 0, f <= 1 else { return nil }
        return CGFloat(f)
    }

    private var havdalahFraction: CGFloat? {
        guard let havdalah,
              let weekStart = weekStartHavdalah,
              let weekEnd = nextWeekHavdalah else { return nil }
        let total = weekEnd.timeIntervalSince(weekStart)
        guard total > 0 else { return nil }
        let elapsed = havdalah.timeIntervalSince(weekStart)
        let f = elapsed / total
        guard f >= 0, f <= 1 else { return nil }
        return CGFloat(f)
    }

    /// The havdalah that opens the current week. If the upcoming havdalah is still
    /// in the future, the previous week's havdalah is 7 days earlier.
    private var weekStartHavdalah: Date? {
        guard let havdalah else { return nil }
        if havdalah <= now {
            return havdalah
        } else {
            return havdalah.addingTimeInterval(-7 * 24 * 3600)
        }
    }

    private var nextWeekHavdalah: Date? {
        guard let weekStartHavdalah else { return nil }
        return weekStartHavdalah.addingTimeInterval(7 * 24 * 3600)
    }

    // MARK: - Animation

    private func animateIn() {
        let target = nowFraction
        dotProgress = 0
        withAnimation(.easeInOut(duration: 1.4).delay(0.2)) {
            dotProgress = target
        }
    }
}

// MARK: - Subviews

private struct SunDot: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.goldAccent.opacity(0.25))
                .frame(width: 28, height: 28)
                .blur(radius: 6)
            Circle()
                .fill(Color.goldAccent)
                .frame(width: 12, height: 12)
        }
    }
}

private struct ShabbatMarker: View {
    let symbol: String
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.surfaceCard)
                .frame(width: 22, height: 22)
                .overlay(
                    Circle().stroke(color.opacity(0.5), lineWidth: 1)
                )
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
        }
    }
}

// MARK: - Geometry

/// An elliptical arc from bottom-left to bottom-right, peaking at the top center.
/// Same parameterisation as ArcMath so the stroke and dot/markers stay aligned.
private struct WeekArcShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let steps = 120
        for i in 0...steps {
            let f = CGFloat(i) / CGFloat(steps)
            let p = ArcMath.point(in: rect.size, fraction: f)
            if i == 0 {
                path.move(to: p)
            } else {
                path.addLine(to: p)
            }
        }
        return path
    }
}

private enum ArcMath {
    /// Maps fraction [0, 1] (left endpoint → right endpoint) to a point on a
    /// semicircular arc that sits inside `size`. The arc bottoms align with
    /// `size.height` and the peak is at the top-centre.
    static func point(in size: CGSize, fraction: CGFloat) -> CGPoint {
        let clamped = max(0, min(1, fraction))
        let rx = size.width / 2
        let ry = size.height
        let t = CGFloat.pi + .pi * clamped
        let x = rx + rx * cos(t)
        let y = size.height + ry * sin(t)
        return CGPoint(x: x, y: y)
    }
}

// MARK: - Preview

#Preview("Mid-week") {
    let cal = Calendar(identifier: .gregorian)
    let now = Date()
    let friday = cal.nextDate(after: now, matching: DateComponents(hour: 19, weekday: 6),
                              matchingPolicy: .nextTime)!
    let saturday = cal.date(byAdding: .day, value: 1, to: friday)!
    let havdalah = cal.date(bySettingHour: 20, minute: 30, second: 0, of: saturday)!

    return ZStack {
        LinearGradient.nightSky.ignoresSafeArea()
        VStack {
            ShabbatWeekArcCard(now: now, candleLighting: friday, havdalah: havdalah)
                .padding(.horizontal, 20)
            Spacer()
        }
    }
}

#Preview("On Shabbat") {
    let cal = Calendar(identifier: .gregorian)
    let now = Date()
    // Pretend candle lighting was last night, havdalah is tonight
    let candle = cal.date(byAdding: .hour, value: -16, to: now)!
    let havdalah = cal.date(byAdding: .hour, value: 6, to: now)!

    return ZStack {
        LinearGradient.nightSky.ignoresSafeArea()
        VStack {
            ShabbatWeekArcCard(now: now, candleLighting: candle, havdalah: havdalah)
                .padding(.horizontal, 20)
            Spacer()
        }
    }
}

import SwiftUI

/// A minimal, modern analog clock view.
struct AnalogClockView: View {
    var size: CGFloat = 280

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) / 2 - 10

                drawClockFace(context: context, center: center, radius: radius)
                drawTickMarks(context: context, center: center, radius: radius)
                drawHands(context: context, center: center, radius: radius, date: timeline.date)
                drawCenterDot(context: context, center: center)
            }
        }
        .frame(width: size, height: size)
    }

    // MARK: - Drawing

    private func drawClockFace(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        let faceRect = CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )

        context.fill(
            Circle().path(in: faceRect),
            with: .color(.clockFaceFill)
        )

        context.stroke(
            Circle().path(in: faceRect),
            with: .color(.clockFaceBorder),
            lineWidth: 0.5
        )
    }

    private func drawTickMarks(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        // Only draw cardinal marks (12, 3, 6, 9)
        for i in [0, 3, 6, 9] {
            let angle = Angle(degrees: Double(i) * 30 - 90)

            let outerR = radius - 8
            let innerR = radius - 20

            let outer = CGPoint(
                x: center.x + outerR * cos(CGFloat(angle.radians)),
                y: center.y + outerR * sin(CGFloat(angle.radians))
            )
            let inner = CGPoint(
                x: center.x + innerR * cos(CGFloat(angle.radians)),
                y: center.y + innerR * sin(CGFloat(angle.radians))
            )

            var path = Path()
            path.move(to: outer)
            path.addLine(to: inner)

            context.stroke(
                path,
                with: .color(.clockTickCardinal.opacity(0.4)),
                lineWidth: 1.5
            )
        }
    }

    private func drawHands(context: GraphicsContext, center: CGPoint, radius: CGFloat, date: Date) {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let second = calendar.component(.second, from: date)
        let nanosecond = calendar.component(.nanosecond, from: date)
        let preciseSecond = Double(second) + Double(nanosecond) / 1_000_000_000

        let minuteAngle = Angle(degrees: Double(minute) * 6 + preciseSecond / 60 * 6 - 90)
        let hourAngle = Angle(degrees: Double(hour % 12) * 30 + Double(minute) / 60 * 30 - 90)

        // Hour hand
        drawHand(
            context: context, center: center,
            length: radius * 0.5, width: 4,
            angle: hourAngle, color: .clockHand
        )

        // Minute hand
        drawHand(
            context: context, center: center,
            length: radius * 0.72, width: 2.5,
            angle: minuteAngle, color: .clockHand
        )

        // Second hand
        let secondAngle = Angle(degrees: preciseSecond * 6 - 90)
        drawHand(
            context: context, center: center,
            length: radius * 0.8, width: 1.5,
            angle: secondAngle, color: .goldAccent
        )
    }

    private let centerDotRadius: CGFloat = 5

    private func drawHand(
        context: GraphicsContext, center: CGPoint,
        length: CGFloat, width: CGFloat,
        angle: Angle, color: Color
    ) {
        let start = CGPoint(
            x: center.x + centerDotRadius * cos(CGFloat(angle.radians)),
            y: center.y + centerDotRadius * sin(CGFloat(angle.radians))
        )
        let end = CGPoint(
            x: center.x + length * cos(CGFloat(angle.radians)),
            y: center.y + length * sin(CGFloat(angle.radians))
        )

        var path = Path()
        path.move(to: start)
        path.addLine(to: end)

        var ctx = context
        ctx.addFilter(.shadow(color: .black.opacity(0.3), radius: 2, x: 1, y: 1))
        ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    private func drawCenterDot(context: GraphicsContext, center: CGPoint) {
        let dotSize = centerDotRadius * 2
        let rect = CGRect(x: center.x - centerDotRadius, y: center.y - centerDotRadius, width: dotSize, height: dotSize)
        context.stroke(Circle().path(in: rect), with: .color(.clockHand), lineWidth: 2)
    }
}

// MARK: - Mini Clock View (for alarm list)

struct MiniClockView: View {
    let hour: Int
    let minute: Int
    var size: CGFloat = 40

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 2

            let faceRect = CGRect(
                x: center.x - radius, y: center.y - radius,
                width: radius * 2, height: radius * 2
            )
            context.fill(Circle().path(in: faceRect), with: .color(.clockFaceFill))
            context.stroke(Circle().path(in: faceRect), with: .color(.clockFaceBorder), lineWidth: 0.5)

            // Hands
            let hourAngle = Angle(degrees: Double(hour % 12) * 30 + Double(minute) / 60 * 30 - 90)
            let minuteAngle = Angle(degrees: Double(minute) * 6 - 90)

            drawMiniHand(context: context, center: center, length: radius * 0.45, angle: hourAngle, color: .clockHand)
            drawMiniHand(context: context, center: center, length: radius * 0.65, angle: minuteAngle, color: .clockHand)

            let dotRect = CGRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4)
            context.fill(Circle().path(in: dotRect), with: .color(.clockHand))
        }
        .frame(width: size, height: size)
    }

    private func drawMiniHand(context: GraphicsContext, center: CGPoint, length: CGFloat, angle: Angle, color: Color) {
        let end = CGPoint(
            x: center.x + length * cos(CGFloat(angle.radians)),
            y: center.y + length * sin(CGFloat(angle.radians))
        )
        var path = Path()
        path.move(to: center)
        path.addLine(to: end)
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
    }
}

// MARK: - Preview

#Preview("Analog Clock") {
    ZStack {
        LinearGradient.nightSky
            .ignoresSafeArea()
        AnalogClockView()
    }
}

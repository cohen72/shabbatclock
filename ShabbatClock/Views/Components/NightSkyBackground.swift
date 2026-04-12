import SwiftUI

/// Beautiful night sky background with moon, stars, and clouds.
struct NightSkyBackground: View {
    @State private var starOpacities: [Double] = (0..<20).map { _ in Double.random(in: 0.3...1.0) }
    @State private var animateTwinkle = false

    var body: some View {
        ZStack {
            // Gradient background
            LinearGradient.nightSky
                .ignoresSafeArea()

            // Stars
            GeometryReader { geometry in
                ForEach(0..<20, id: \.self) { index in
                    StarView(size: CGFloat.random(in: 2...6))
                        .opacity(animateTwinkle ? starOpacities[index] : starOpacities[(index + 1) % 20])
                        .position(
                            x: starPositions[index].x * geometry.size.width,
                            y: starPositions[index].y * geometry.size.height
                        )
                }
            }

            // Moon with glow - positioned in top right corner
            GeometryReader { geometry in
                MoonView()
                    .frame(width: 100, height: 100)
                    .position(
                        x: geometry.size.width - 50,
                        y: 80
                    )
            }

            // Cloud at bottom
            VStack {
                Spacer()
                CloudView()
                    .offset(y: 50)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                animateTwinkle = true
            }
        }
    }

    private var starPositions: [CGPoint] {
        [
            CGPoint(x: 0.1, y: 0.1),
            CGPoint(x: 0.25, y: 0.05),
            CGPoint(x: 0.4, y: 0.12),
            CGPoint(x: 0.6, y: 0.08),
            CGPoint(x: 0.75, y: 0.15),
            CGPoint(x: 0.9, y: 0.1),
            CGPoint(x: 0.15, y: 0.25),
            CGPoint(x: 0.35, y: 0.2),
            CGPoint(x: 0.55, y: 0.22),
            CGPoint(x: 0.8, y: 0.28),
            CGPoint(x: 0.05, y: 0.4),
            CGPoint(x: 0.2, y: 0.45),
            CGPoint(x: 0.45, y: 0.38),
            CGPoint(x: 0.7, y: 0.42),
            CGPoint(x: 0.95, y: 0.35),
            CGPoint(x: 0.12, y: 0.55),
            CGPoint(x: 0.3, y: 0.52),
            CGPoint(x: 0.5, y: 0.58),
            CGPoint(x: 0.85, y: 0.5),
            CGPoint(x: 0.65, y: 0.55),
        ]
    }
}

// MARK: - Star View

struct StarView: View {
    let size: CGFloat
    var color: Color = .goldAccent

    var body: some View {
        Image(systemName: "star.fill")
            .font(.system(size: size))
            .foregroundStyle(color)
            .shadow(color: color.opacity(0.8), radius: size / 2)
    }
}

// MARK: - Moon View

struct MoonView: View {
    var body: some View {
        ZStack {
            // Outer glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.3), .clear],
                        center: .center,
                        startRadius: 30,
                        endRadius: 80
                    )
                )
                .frame(width: 160, height: 160)

            // Moon body
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.white, Color(hex: "E8E8E8")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 60, height: 60)
                .shadow(color: .white.opacity(0.5), radius: 20)

            // Moon crescent shadow
            Circle()
                .fill(Color.primaryDark.opacity(0.3))
                .frame(width: 60, height: 60)
                .offset(x: 10, y: -5)
                .mask(
                    Circle()
                        .frame(width: 60, height: 60)
                )

            // Decorative stars around moon
            StarView(size: 12, color: .goldAccent)
                .offset(x: -30, y: -20)

            StarView(size: 8, color: .goldAccent)
                .offset(x: 25, y: -35)

            StarView(size: 6, color: .white)
                .offset(x: -40, y: 15)
        }
    }
}

// MARK: - Cloud View

struct CloudView: View {
    var body: some View {
        ZStack {
            // Main cloud shape using circles
            HStack(spacing: -30) {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 80, height: 80)

                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 120, height: 120)
                    .offset(y: 20)

                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 100, height: 100)
                    .offset(y: 10)

                Circle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 70, height: 70)
            }
        }
        .blur(radius: 10)
    }
}

// MARK: - Night Sky Decorations (without background gradient)

/// Just the stars, moon, and clouds without the gradient background.
/// Use this when you need to manage the background separately.
struct NightSkyDecorations: View {
    @State private var starOpacities: [Double] = (0..<20).map { _ in Double.random(in: 0.3...1.0) }
    @State private var animateTwinkle = false

    var body: some View {
        ZStack {
            // Stars
            GeometryReader { geometry in
                ForEach(0..<20, id: \.self) { index in
                    StarView(size: CGFloat.random(in: 2...6))
                        .opacity(animateTwinkle ? starOpacities[index] : starOpacities[(index + 1) % 20])
                        .position(
                            x: starPositions[index].x * geometry.size.width,
                            y: starPositions[index].y * geometry.size.height
                        )
                }
            }

            // Moon with glow - positioned in top right corner
            GeometryReader { geometry in
                MoonView()
                    .frame(width: 100, height: 100)
                    .position(
                        x: geometry.size.width - 50,
                        y: 80
                    )
            }

            // Cloud at bottom
            VStack {
                Spacer()
                CloudView()
                    .offset(y: 50)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                animateTwinkle = true
            }
        }
    }

    private var starPositions: [CGPoint] {
        [
            CGPoint(x: 0.1, y: 0.1),
            CGPoint(x: 0.25, y: 0.05),
            CGPoint(x: 0.4, y: 0.12),
            CGPoint(x: 0.6, y: 0.08),
            CGPoint(x: 0.75, y: 0.15),
            CGPoint(x: 0.9, y: 0.1),
            CGPoint(x: 0.15, y: 0.25),
            CGPoint(x: 0.35, y: 0.2),
            CGPoint(x: 0.55, y: 0.22),
            CGPoint(x: 0.8, y: 0.28),
            CGPoint(x: 0.05, y: 0.4),
            CGPoint(x: 0.2, y: 0.45),
            CGPoint(x: 0.45, y: 0.38),
            CGPoint(x: 0.7, y: 0.42),
            CGPoint(x: 0.95, y: 0.35),
            CGPoint(x: 0.12, y: 0.55),
            CGPoint(x: 0.3, y: 0.52),
            CGPoint(x: 0.5, y: 0.58),
            CGPoint(x: 0.85, y: 0.5),
            CGPoint(x: 0.65, y: 0.55),
        ]
    }
}

// MARK: - Stars Only Background (no moon/clouds)

/// Simple stars-only background for cleaner layouts.
struct StarsOnlyBackground: View {
    @State private var starOpacities: [Double] = (0..<30).map { _ in Double.random(in: 0.2...0.8) }
    @State private var animateTwinkle = false

    var body: some View {
        GeometryReader { geometry in
            ForEach(0..<30, id: \.self) { index in
                Circle()
                    .fill(index % 3 == 0 ? Color.goldAccent : Color.white)
                    .frame(width: CGFloat.random(in: 1...3), height: CGFloat.random(in: 1...3))
                    .opacity(animateTwinkle ? starOpacities[index] : starOpacities[(index + 1) % 30])
                    .position(
                        x: starPositions[index].x * geometry.size.width,
                        y: starPositions[index].y * geometry.size.height
                    )
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                animateTwinkle = true
            }
        }
    }

    private var starPositions: [CGPoint] {
        [
            CGPoint(x: 0.08, y: 0.08),
            CGPoint(x: 0.22, y: 0.05),
            CGPoint(x: 0.38, y: 0.10),
            CGPoint(x: 0.55, y: 0.06),
            CGPoint(x: 0.72, y: 0.12),
            CGPoint(x: 0.88, y: 0.08),
            CGPoint(x: 0.12, y: 0.18),
            CGPoint(x: 0.32, y: 0.15),
            CGPoint(x: 0.48, y: 0.20),
            CGPoint(x: 0.68, y: 0.16),
            CGPoint(x: 0.85, y: 0.22),
            CGPoint(x: 0.05, y: 0.32),
            CGPoint(x: 0.18, y: 0.28),
            CGPoint(x: 0.42, y: 0.35),
            CGPoint(x: 0.62, y: 0.30),
            CGPoint(x: 0.78, y: 0.38),
            CGPoint(x: 0.92, y: 0.33),
            CGPoint(x: 0.10, y: 0.48),
            CGPoint(x: 0.28, y: 0.52),
            CGPoint(x: 0.45, y: 0.45),
            CGPoint(x: 0.58, y: 0.55),
            CGPoint(x: 0.75, y: 0.48),
            CGPoint(x: 0.90, y: 0.52),
            CGPoint(x: 0.15, y: 0.65),
            CGPoint(x: 0.35, y: 0.68),
            CGPoint(x: 0.52, y: 0.72),
            CGPoint(x: 0.70, y: 0.65),
            CGPoint(x: 0.82, y: 0.70),
            CGPoint(x: 0.25, y: 0.82),
            CGPoint(x: 0.65, y: 0.85),
        ]
    }
}

// MARK: - Preview

#Preview {
    NightSkyBackground()
}

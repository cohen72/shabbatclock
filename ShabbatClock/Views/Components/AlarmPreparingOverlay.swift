import SwiftUI

/// Full-screen blocking overlay shown while an alarm is being prepared (sound
/// composition + AlarmKit scheduling). Intentionally pleasant — gold pulse,
/// orbiting note symbols — so the 1–3s composer wait reads as polish, not lag.
///
/// Caller controls visibility via the `isPresented` binding. To avoid a flash
/// when work completes faster than perception (~200ms), the caller should keep
/// the overlay up for at least ~800ms total.
struct AlarmPreparingOverlay: View {
    @Binding var isPresented: Bool
    var title: LocalizedStringKey = "Preparing your alarm"
    var subtitle: LocalizedStringKey = "Composing your sound…"

    @State private var pulseScale: CGFloat = 0.85
    @State private var ringRotation: Double = 0
    @State private var noteOpacity: Double = 0.4

    var body: some View {
        if isPresented {
            ZStack {
                // Dim + blur the background
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .transition(.opacity)

                // Card
                VStack(spacing: 22) {
                    animatedIcon

                    VStack(spacing: 6) {
                        Text(title)
                            .font(AppFont.header(20))
                            .foregroundStyle(.textPrimary)
                            .multilineTextAlignment(.center)
                        Text(subtitle)
                            .font(AppFont.body(14))
                            .foregroundStyle(.textSecondary)
                            .multilineTextAlignment(.center)
                            .opacity(noteOpacity)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 32)
                .frame(maxWidth: 280)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.surfaceCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.goldAccent.opacity(0.25), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 30, x: 0, y: 12)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
            .animation(.easeInOut(duration: 0.25), value: isPresented)
            .allowsHitTesting(true)
            .onAppear { startAnimations() }
        }
    }

    private var animatedIcon: some View {
        ZStack {
            // Outer rotating ring
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(
                    LinearGradient(
                        colors: [Color.goldAccent, Color.goldAccent.opacity(0.0)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: 88, height: 88)
                .rotationEffect(.degrees(ringRotation))

            // Pulsing inner glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.goldAccent.opacity(0.45),
                            Color.goldAccent.opacity(0.0)
                        ],
                        center: .center,
                        startRadius: 4,
                        endRadius: 50
                    )
                )
                .frame(width: 88, height: 88)
                .scaleEffect(pulseScale)
                .opacity(0.85)

            // Center icon
            Image(systemName: "music.note")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.goldAccent)
                .scaleEffect(pulseScale)
        }
        .frame(height: 100)
    }

    private func startAnimations() {
        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
            pulseScale = 1.05
        }
        withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
            ringRotation = 360
        }
        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
            noteOpacity = 1.0
        }
    }
}

#Preview {
    ZStack {
        Color.backgroundPrimary.ignoresSafeArea()
        AlarmPreparingOverlay(isPresented: .constant(true))
    }
}

import SwiftUI

/// Full-screen view displayed when an alarm is firing.
struct AlarmActiveView: View {
    @EnvironmentObject private var alarmScheduler: AlarmScheduler
    @State private var animatePulse = false

    var body: some View {
        ZStack {
            // Background
            LinearGradient.nightSky
                .ignoresSafeArea()

            // Pulsing glow effect
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.accentPurple.opacity(0.3), .clear],
                        center: .center,
                        startRadius: 50,
                        endRadius: animatePulse ? 300 : 200
                    )
                )
                .scaleEffect(animatePulse ? 1.2 : 1.0)
                .opacity(animatePulse ? 0.5 : 0.8)
                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: animatePulse)

            VStack(spacing: 32) {
                Spacer()

                // Alarm icon with pulse animation
                Image(systemName: "alarm.waves.left.and.right")
                    .font(.system(size: 60))
                    .foregroundColor(.goldAccent)
                    .scaleEffect(animatePulse ? 1.1 : 1.0)

                // Time display
                Text(currentTimeString)
                    .font(AppFont.timeDisplay(72))
                    .foregroundColor(.textPrimary)

                // Alarm label
                if let alarm = alarmScheduler.firingAlarm {
                    Text(alarm.label)
                        .font(AppFont.header(24))
                        .foregroundColor(.textSecondary)
                }

                Spacer()

                // Countdown ring
                countdownView

                Spacer()

                // Stop button (for non-Shabbat use)
                stopButton

                // Note about auto-shutoff
                Text("Alarm will stop automatically")
                    .font(AppFont.caption(13))
                    .foregroundStyle(.textSecondary.opacity(0.6))
                    .padding(.bottom, 40)
            }
            .padding(.horizontal, 32)
        }
        .onAppear {
            animatePulse = true
        }
    }

    // MARK: - Countdown View

    private var countdownView: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Color.surfaceBorder, lineWidth: 8)
                .frame(width: 180, height: 180)

            // Progress ring
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(
                        colors: [.accentPurple, .goldAccent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .frame(width: 180, height: 180)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: progress)

            // Countdown text
            VStack(spacing: 4) {
                Text(countdownString)
                    .font(AppFont.timeDisplay(40))
                    .foregroundColor(.textPrimary)
                    .monospacedDigit()

                Text("remaining")
                    .font(AppFont.caption(12))
                    .foregroundStyle(.textSecondary)
            }
        }
    }

    // MARK: - Stop Button

    private var stopButton: some View {
        Button {
            alarmScheduler.stopAlarm()
        } label: {
            Text("Stop Alarm")
                .font(AppFont.body(16))
                .fontWeight(.semibold)
                .foregroundStyle(.white) // Always white on accent background
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.accentPurple)
                        .shadow(color: .accentPurple.opacity(0.4), radius: 10, y: 4)
                )
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Computed Properties

    private var currentTimeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        return formatter.string(from: Date())
    }

    private var progress: CGFloat {
        let total: CGFloat = 30
        let remaining = CGFloat(alarmScheduler.shutoffCountdown)
        return remaining / total
    }

    private var countdownString: String {
        let countdown = alarmScheduler.shutoffCountdown
        let minutes = countdown / 60
        let seconds = countdown % 60

        if minutes > 0 {
            return String(format: "%d:%02d", minutes, seconds)
        } else {
            return String(format: "0:%02d", seconds)
        }
    }
}

// MARK: - Preview

#Preview {
    AlarmActiveView()
        .environmentObject(AlarmScheduler.shared)
}

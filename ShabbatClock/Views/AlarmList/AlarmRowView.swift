import SwiftUI

/// A row displaying a single alarm in the list.
struct AlarmRowView: View {
    @Bindable var alarm: Alarm
    var onToggle: ((Bool) -> Void)?

    var body: some View {
        HStack(spacing: 16) {
            // Time and label
            VStack(alignment: .leading, spacing: 6) {
                // Time
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(alarm.timeString)
                        .font(.system(size: 38, weight: .bold, design: .default))
                        .foregroundStyle(alarm.isEnabled ? .textPrimary : .textSecondary.opacity(0.6))

                    Text(alarm.periodString)
                        .font(.system(size: 16, weight: .medium, design: .default))
                        .foregroundStyle(.textSecondary.opacity(alarm.isEnabled ? 0.7 : 0.4))
                }

                // Label
                Text(alarm.label)
                    .font(.system(size: 14, weight: .regular, design: .default))
                    .foregroundStyle(.textSecondary.opacity(alarm.isEnabled ? 0.85 : 0.4))

                // Repeat days
                if !alarm.repeatDays.isEmpty {
                    Text(alarm.repeatDaysString)
                        .font(.system(size: 12, weight: .medium, design: .default))
                        .foregroundStyle(.goldAccent.opacity(alarm.isEnabled ? 0.8 : 0.4))
                }
            }

            Spacer(minLength: 12)

            // Toggle
            Toggle("", isOn: $alarm.isEnabled)
                .labelsHidden()
                .tint(.accentPurple)
                .onChange(of: alarm.isEnabled) { _, newValue in
                    onToggle?(newValue)
                }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(alarm.isEnabled ? Color.surfaceCard : Color.surfaceSubtle)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                            Color.surfaceBorder.opacity(alarm.isEnabled ? 1 : 0.5),
                            lineWidth: 0.5
                        )
                )
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: alarm.isEnabled)
    }
}

// MARK: - Compact Row (for smaller displays)

struct AlarmRowCompact: View {
    @Bindable var alarm: Alarm

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(alarm.timeString)
                        .font(AppFont.header(22))
                        .foregroundStyle(alarm.isEnabled ? .textPrimary : .textSecondary)

                    Text(alarm.periodString)
                        .font(AppFont.caption(11))
                        .foregroundStyle(.textSecondary)
                }

                Text(alarm.label)
                    .font(AppFont.caption(12))
                    .foregroundStyle(.textSecondary)
            }

            Spacer()

            Toggle("", isOn: $alarm.isEnabled)
                .labelsHidden()
                .tint(.accentPurple)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassMorphic(cornerRadius: 12, opacity: alarm.isEnabled ? 0.06 : 0.03)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        LinearGradient.nightSky
            .ignoresSafeArea()

        VStack(spacing: 12) {
            AlarmRowView(
                alarm: Alarm(
                    hour: 7,
                    minute: 30,
                    isEnabled: true,
                    label: "Shacharis",
                    repeatDays: [6]
                )
            )

            AlarmRowView(
                alarm: Alarm(
                    hour: 9,
                    minute: 0,
                    isEnabled: false,
                    label: "Late Shacharis",
                    repeatDays: []
                )
            )
        }
        .padding()
    }
}

import SwiftUI

/// A row displaying a single alarm in the list.
struct AlarmRowView: View {
    @Bindable var alarm: Alarm
    @Environment(AlarmKitService.self) private var alarmService
    var onToggle: ((Bool) -> Void)?

    var body: some View {
        if alarm.isDeleted {
            EmptyView()
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        HStack(spacing: 16) {
            // Time and label
            VStack(alignment: .leading, spacing: 6) {
                // Time
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(alarm.timeString)
                        .font(.system(size: 56, weight: .thin, design: .default))
                        .monospacedDigit()
                        .foregroundStyle(alarm.isEnabled ? .textPrimary : .textSecondary.opacity(0.6))

                    Text(alarm.periodString)
                        .font(.system(size: 22, weight: .thin, design: .default))
                        .foregroundStyle(.textSecondary.opacity(alarm.isEnabled ? 0.8 : 0.4))
                }

                // Label + duration
                HStack(spacing: 6) {
                    Text(alarm.label)
                        .font(.system(size: 14, weight: .regular, design: .default))
                        .foregroundStyle(.textSecondary.opacity(alarm.isEnabled ? 0.85 : 0.4))

                    HStack(spacing: 3) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 9))
                        Text(durationLabel)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .monospacedDigit()
                    }
                    .foregroundStyle(.goldAccent.opacity(alarm.isEnabled ? 0.75 : 0.35))
                }

                // Schedule: repeat days OR next fire date
                Text(scheduleLabel)
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundStyle(.goldAccent.opacity(alarm.isEnabled ? 0.8 : 0.4))
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

    private var durationLabel: String {
        let seconds = alarm.alarmDurationSeconds
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        return "\(minutes)m"
    }

    private var scheduleLabel: String {
        // Repeat days take precedence (e.g., "Tue, Thu, Sat")
        if !alarm.repeatDays.isEmpty {
            return alarm.repeatDaysString
        }
        // One-time alarm — show relative date
        let locale = AppLanguage.current.effectiveLocale
        let calendar = Calendar.current
        let now = Date()
        guard let fireDate = alarm.nextFireDate(from: now) else {
            // Disabled alarm — still show a schedule hint
            return oneTimeFallbackLabel(locale: locale, calendar: calendar, now: now)
        }
        return relativeDateLabel(for: fireDate, now: now, calendar: calendar, locale: locale)
    }

    private func oneTimeFallbackLabel(locale: Locale, calendar: Calendar, now: Date) -> String {
        // Alarm is disabled — compute what "would" be the next fire based on time only.
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = alarm.hour
        components.minute = alarm.minute
        guard let candidate = calendar.date(from: components) else {
            return String(localized: "Once")
        }
        let target = candidate <= now ? calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate : candidate
        return relativeDateLabel(for: target, now: now, calendar: calendar, locale: locale)
    }

    private func relativeDateLabel(for date: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        if calendar.isDateInToday(date) {
            return String(localized: "Today")
        }
        if calendar.isDateInTomorrow(date) {
            return String(localized: "Tomorrow")
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        // Within the next 6 days → weekday name (e.g. "Thursday")
        if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day, days < 7 {
            formatter.setLocalizedDateFormatFromTemplate("EEEE")
        } else {
            // Further out → short date (e.g. "Thu, Apr 16")
            formatter.setLocalizedDateFormatFromTemplate("EEE, MMM d")
        }
        return formatter.string(from: date)
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
    .environment(AlarmKitService.shared)
}

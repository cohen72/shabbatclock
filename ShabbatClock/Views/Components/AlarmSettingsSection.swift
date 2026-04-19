import SwiftUI

/// Shared alarm settings used by both AlarmEditView and ZmanAlarmSheet.
/// Contains: sound picker, auto-stop duration, label, vibration hint.
struct AlarmSettingsSection: View {
    @Binding var soundName: String
    @Binding var alarmDuration: Int
    @Binding var label: String

    @Environment(AlarmKitService.self) private var alarmService
    @AppStorage("isPremium") private var isPremium = false

    private var alarmDurationOptions: [(String, Int)] {
        var options: [(String, Int)] = [
            ("15 sec", 15),
            ("30 sec", 30),
            ("1 min", 60),
            ("2 min", 120),
            ("5 min", 300),
            ("10 min", 600),
        ]
        if isPremium {
            options.append(contentsOf: [
                ("15 min", 900),
                ("30 min", 1800),
            ])
        }
        return options
    }

    var body: some View {
        VStack(spacing: 16) {
            // Label
            labelRow

            // Sound
            soundRow

            // Auto-stop duration
            alarmDurationRow

            // Vibration hint
            vibrationHintRow
        }
    }

    // MARK: - Label

    private var labelRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Label")
                .font(AppFont.caption(12))
                .foregroundStyle(.textSecondary)
                .padding(.leading, 4)

            TextField("Alarm", text: $label)
                .font(AppFont.body())
                .foregroundStyle(.textPrimary)
                .submitLabel(.done)
                .padding(16)
                .themeCard(cornerRadius: 14)
                .tint(.accentPurple)
        }
    }

    // MARK: - Sound

    private var soundRow: some View {
        NavigationLink {
            SoundPickerView(selectedSoundName: $soundName)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sound")
                        .font(AppFont.caption(12))
                        .foregroundStyle(.textSecondary)

                    HStack(spacing: 8) {
                        Image(systemName: "music.note")
                            .font(.system(size: 14))
                            .foregroundStyle(.accentPurple)

                        Text(soundName)
                            .font(AppFont.body())
                            .foregroundStyle(.textPrimary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.forward")
                    .font(.system(size: 14))
                    .foregroundStyle(.textSecondary)
            }
            .padding(16)
            .themeCard(cornerRadius: 14)
        }
    }

    // MARK: - Auto-Stop Duration

    private var alarmDurationRow: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Auto-Stop")
                        .font(AppFont.caption(12))
                        .foregroundStyle(.textSecondary)

                    Text("Stops alarm automatically")
                        .font(.system(size: 11))
                        .foregroundStyle(.textSecondary.opacity(0.6))
                        .lineLimit(1)
                }

                Spacer()

                if alarmService.isFallbackMode {
                    Text("30 sec")
                        .font(AppFont.body())
                        .foregroundStyle(.textSecondary)
                } else {
                    Picker("", selection: $alarmDuration) {
                        ForEach(alarmDurationOptions, id: \.1) { option in
                            Text(option.0).tag(option.1)
                        }
                    }
                    .tint(.accentPurple)
                }
            }
            .padding(16)
            .themeCard(cornerRadius: 14)

            // Fallback mode hint
            if alarmService.isFallbackMode {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                        Text("Allow alarms in Settings for longer durations")
                            .font(.system(size: 11))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.forward")
                            .font(.system(size: 9))
                    }
                    .foregroundStyle(.goldAccent)
                    .padding(.horizontal, 16)
                }
            }

        }
    }

    // MARK: - Vibration Hint

    private var vibrationHintRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "iphone.radiowaves.left.and.right")
                .font(.system(size: 12))
                .foregroundStyle(.textSecondary.opacity(0.5))
            Text("To disable vibration, go to Settings › Sounds & Haptics")
                .font(.system(size: 11))
                .foregroundStyle(.textSecondary.opacity(0.5))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
}

// MARK: - Auto-Stop Background Banner

/// Banner reminding users to keep the app in the background for auto-stop to work.
/// Placed at the top of alarm edit/create screens.
struct AutoStopBackgroundBanner: View {
    @Environment(AlarmKitService.self) private var alarmService

    var body: some View {
        if !alarmService.isFallbackMode {
            HStack(spacing: 12) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.goldAccent)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Shabbat Mode")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.textPrimary)
                    Text("Keep the app running in the background before Shabbat so alarms auto-stop.")
                        .font(.system(size: 11))
                        .foregroundStyle(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.goldAccent.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.goldAccent.opacity(0.2), lineWidth: 0.5)
                    )
            )
        }
    }
}

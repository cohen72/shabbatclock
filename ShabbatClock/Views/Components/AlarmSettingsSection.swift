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

            // Auto-stop background requirement hint
            if !alarmService.isFallbackMode {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                    Text("Keep the app open in the background for auto-stop to work. Don't force-quit before Shabbat.")
                        .font(.system(size: 11))
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
                .foregroundStyle(.textSecondary.opacity(0.5))
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Vibration Hint

    private var vibrationHintRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "iphone.radiowaves.left.and.right")
                .font(.system(size: 14))
                .foregroundStyle(.textSecondary)
            Text("Vibration is controlled in iOS Settings")
                .font(.system(size: 12))
                .foregroundStyle(.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

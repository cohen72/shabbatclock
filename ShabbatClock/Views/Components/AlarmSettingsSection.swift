import SwiftUI

/// Shared alarm settings used by both AlarmEditView and ZmanAlarmSheet.
/// Contains: sound picker, auto-stop duration, label, ring setup education.
struct AlarmSettingsSection: View {
    @Binding var soundName: String
    @Binding var alarmDuration: Int
    @Binding var label: String

    @Environment(AlarmKitService.self) private var alarmService
    @Environment(\.modelContext) private var modelContext
    @State private var showingRingSetup = false

    private var alarmDurationOptions: [(String, Int)] {
        [
            ("15 sec", 15),
            ("30 sec", 30),
            ("1 min", 60),
            ("2 min", 120),
            ("3 min", 180),
            ("5 min", 300),
        ]
    }

    var body: some View {
        VStack(spacing: 16) {
            // Label
            labelRow

            // Sound
            soundRow

            // Auto-stop duration
            alarmDurationRow

            // Ring setup education
            ringSetupCard
        }
        .onAppear {
            // Migrate legacy duration values that no longer exist in the picker
            // (10/15/30 min options were removed). Snap to the largest available value.
            let validValues = alarmDurationOptions.map(\.1)
            if !validValues.contains(alarmDuration) {
                alarmDuration = validValues.last ?? 30
            }
        }
        .sheet(isPresented: $showingRingSetup) {
            NavigationStack {
                RingSetupView(mode: .standalone)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                showingRingSetup = false
                            }
                            .foregroundStyle(.accentPurple)
                        }
                    }
            }
            .applyLanguageOverride(AppLanguage.current)
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

                        Text(AlarmSound.displayName(for: soundName, in: modelContext))
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

    // MARK: - Ring Setup Education

    /// Compact teaser explaining the silencer mechanism + vibration caveat,
    /// with a tap target opening the full RingSetupView walkthrough.
    private var ringSetupCard: some View {
        Button {
            showingRingSetup = true
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.goldAccent)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text("About auto-stop")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.textPrimary)
                    Text("For a clean silent shut-off, turn off vibration in iOS Settings.")
                        .font(.system(size: 11))
                        .foregroundStyle(.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Learn how →")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.accentPurple)
                        .padding(.top, 2)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.goldAccent.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.goldAccent.opacity(0.2), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}


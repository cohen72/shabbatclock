import SwiftUI

/// Sound picker view with categories and preview functionality.
struct SoundPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedSoundName: String

    @State private var previewingSound: AlarmSound?
    @AppStorage("isPremium") private var isPremium = false

    var body: some View {
        ZStack {
            LinearGradient.nightSky
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                headerView

                // Sound list
                ScrollView {
                    LazyVStack(spacing: 24) {
                        ForEach(AlarmSound.Category.allCases, id: \.self) { category in
                            if let sounds = AlarmSound.byCategory[category], !sounds.isEmpty {
                                SoundCategorySection(
                                    category: category,
                                    sounds: sounds,
                                    selectedSoundName: $selectedSoundName,
                                    previewingSound: $previewingSound,
                                    isPremium: isPremium
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            }
        }
        .onDisappear {
            AudioManager.shared.stopPreview()
        }
    }

    private var headerView: some View {
        HStack {
            Button("Cancel") {
                AudioManager.shared.stopPreview()
                dismiss()
            }
            .foregroundStyle(.textSecondary)

            Spacer()

            Text("Alarm Sound")
                .font(AppFont.header(18))
                .foregroundStyle(.textPrimary)

            Spacer()

            Button("Done") {
                AudioManager.shared.stopPreview()
                dismiss()
            }
            .foregroundStyle(.accentPurple)
            .fontWeight(.semibold)
        }
        .padding()
    }
}

// MARK: - Category Section

struct SoundCategorySection: View {
    let category: AlarmSound.Category
    let sounds: [AlarmSound]
    @Binding var selectedSoundName: String
    @Binding var previewingSound: AlarmSound?
    let isPremium: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Category header
            HStack(spacing: 8) {
                Image(systemName: category.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(.accentPurple)

                Text(category.rawValue)
                    .font(AppFont.body(15))
                    .fontWeight(.semibold)
                    .foregroundStyle(.textPrimary)

                Spacer()

                // Show premium badge if category has premium sounds
                if sounds.contains(where: { $0.isPremium }) && !isPremium {
                    PremiumBadge()
                }
            }

            // Sounds
            VStack(spacing: 1) {
                ForEach(sounds) { sound in
                    SoundRow(
                        sound: sound,
                        isSelected: selectedSoundName == sound.name,
                        isPreviewing: previewingSound?.id == sound.id,
                        isLocked: sound.isPremium && !isPremium
                    ) {
                        handleSoundTap(sound)
                    } onPreview: {
                        handlePreview(sound)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func handleSoundTap(_ sound: AlarmSound) {
        if sound.isPremium && !isPremium {
            // Show premium prompt
            return
        }
        selectedSoundName = sound.name
    }

    private func handlePreview(_ sound: AlarmSound) {
        if sound.isPremium && !isPremium {
            return
        }

        if previewingSound?.id == sound.id {
            // Stop preview
            AudioManager.shared.stopPreview()
            previewingSound = nil
        } else {
            // Start preview
            AudioManager.shared.stopPreview()
            AudioManager.shared.playPreview(sound: sound)
            previewingSound = sound
        }
    }
}

// MARK: - Sound Row

struct SoundRow: View {
    let sound: AlarmSound
    let isSelected: Bool
    let isPreviewing: Bool
    let isLocked: Bool
    let onTap: () -> Void
    let onPreview: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Sound name
                Text(sound.name)
                    .font(AppFont.body())
                    .foregroundColor(isLocked ? .textSecondary.opacity(0.5) : .textPrimary)

                Spacer()

                // Lock icon for premium
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.goldAccent.opacity(0.7))
                }

                // Preview button
                Button(action: onPreview) {
                    Image(systemName: isPreviewing ? "stop.fill" : "play.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(isLocked ? .textSecondary.opacity(0.3) : .accentPurple)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.1))
                        )
                }
                .disabled(isLocked)

                // Checkmark for selected
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.accentPurple)
                        .fontWeight(.semibold)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white.opacity(isSelected ? 0.1 : 0.05))
        }
        .disabled(isLocked)
    }
}

// MARK: - Premium Badge

struct PremiumBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill")
                .font(.system(size: 8))
            Text("Premium")
                .font(AppFont.caption(10))
        }
        .foregroundStyle(.goldAccent)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.goldAccent.opacity(0.15))
        )
    }
}

// MARK: - Inline Sound Picker (for alarm edit view)

struct InlineSoundPicker: View {
    @Binding var selectedSoundName: String
    @State private var showingPicker = false

    var body: some View {
        Button {
            showingPicker = true
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

                        Text(selectedSoundName)
                            .font(AppFont.body())
                            .foregroundStyle(.textPrimary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundStyle(.textSecondary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                    )
            )
        }
        .sheet(isPresented: $showingPicker) {
            SoundPickerView(selectedSoundName: $selectedSoundName)
        }
    }
}

// MARK: - Preview

#Preview {
    SoundPickerView(selectedSoundName: .constant("Lecha Dodi"))
}

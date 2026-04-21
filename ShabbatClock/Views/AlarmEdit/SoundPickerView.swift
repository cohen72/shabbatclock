import SwiftUI
import SwiftData

/// Sound picker view with categories and preview functionality.
/// "My Recordings" appears at the top — premium-only feature for user-recorded sounds.
struct SoundPickerView: View {
    @Binding var selectedSoundName: String

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CustomSound.createdAt, order: .reverse) private var customSounds: [CustomSound]

    @State private var previewingSound: AlarmSound?
    @State private var previewingCustomFileName: String?
    @State private var showingPremium = false
    @State private var showingRecorder = false
    @State private var pendingDeletion: CustomSound?
    @ObservedObject private var storeManager = StoreManager.shared

    var body: some View {
        ZStack {
            LinearGradient.nightSky
                .ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: 24) {
                    // "My Recordings" section — always visible, gated for free users
                    myRecordingsSection

                    ForEach(AlarmSound.Category.allCases, id: \.self) { category in
                        if let sounds = AlarmSound.byCategory[category], !sounds.isEmpty {
                            SoundCategorySection(
                                category: category,
                                sounds: sounds,
                                selectedSoundName: $selectedSoundName,
                                previewingSound: $previewingSound,
                                isPremium: storeManager.isPremium,
                                onLockedTap: { showingPremium = true },
                                onAnyPreviewTap: stopCustomPreview
                            )
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Alarm Sound")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPremium) {
            PremiumView()
                .applyLanguageOverride(AppLanguage.current)
        }
        .sheet(isPresented: $showingRecorder) {
            SoundRecordingView { _ in
                // Selection happens explicitly via tap on the row — we don't auto-select
                // so users can review before committing. (No-op here.)
            }
        }
        .confirmationDialog(
            deleteDialogTitle,
            isPresented: deleteDialogBinding,
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { custom in
            Button("Delete", role: .destructive) {
                confirmDelete(custom)
            }
            Button("Cancel", role: .cancel) {
                pendingDeletion = nil
            }
        } message: { custom in
            Text(deleteDialogMessage(for: custom))
        }
        .onAppear {
            AudioManager.shared.onPreviewStopped = { [self] in
                previewingSound = nil
                previewingCustomFileName = nil
            }
        }
        .onDisappear {
            AudioManager.shared.stopPreview()
            AudioManager.shared.onPreviewStopped = nil
        }
    }

    // MARK: - My Recordings

    private var myRecordingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.goldAccent)

                Text("My Recordings")
                    .font(AppFont.body(15))
                    .fontWeight(.semibold)
                    .foregroundStyle(.textPrimary)

                if !storeManager.isPremium {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.goldAccent.opacity(0.7))
                }
            }

            VStack(spacing: 1) {
                // Record button (premium-gated)
                recordNewButton

                // Existing recordings (premium users only see these)
                if storeManager.isPremium {
                    ForEach(customSounds) { custom in
                        customSoundRow(custom)
                    }
                } else if customSounds.isEmpty {
                    teaserCard
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var recordNewButton: some View {
        Button {
            if storeManager.isPremium {
                showingRecorder = true
            } else {
                showingPremium = true
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.goldAccent)
                    .frame(width: 24)

                Text("Record New Sound")
                    .font(AppFont.body())
                    .foregroundStyle(.textPrimary)

                Spacer()

                if storeManager.isPremium {
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 12))
                        .foregroundStyle(.textSecondary)
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.goldAccent.opacity(0.7))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surfaceSubtle)
            .contentShape(Rectangle())
        }
    }

    private var teaserCard: some View {
        Button {
            showingPremium = true
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Make alarms personal")
                    .font(AppFont.body(14))
                    .fontWeight(.semibold)
                    .foregroundStyle(.textPrimary)

                Text("Record your own voice, a family member, or a favorite melody to wake up to.")
                    .font(AppFont.caption(12))
                    .foregroundStyle(.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 4) {
                    Text("Unlock with Premium")
                        .font(AppFont.caption(12))
                        .fontWeight(.semibold)
                        .foregroundStyle(.goldAccent)
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.goldAccent)
                }
                .padding(.top, 2)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surfaceSubtle)
        }
    }

    private func customSoundRow(_ custom: CustomSound) -> some View {
        let alarmSoundName = AlarmSound.customSoundName(fileName: custom.fileName)
        let isSelected = selectedSoundName == alarmSoundName
        let isPreviewing = previewingCustomFileName == custom.fileName

        return HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark" : "")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.accentPurple)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(custom.name)
                    .font(AppFont.body())
                    .foregroundStyle(.textPrimary)
                Text(durationString(custom.duration))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.textSecondary)
            }

            Spacer()

            Button {
                if isPreviewing {
                    AudioManager.shared.stopPreview()
                    previewingCustomFileName = nil
                } else {
                    AudioManager.shared.stopPreview()
                    previewingSound = nil
                    AudioManager.shared.playPreview(customFileName: custom.fileName)
                    previewingCustomFileName = custom.fileName
                }
            } label: {
                Image(systemName: isPreviewing ? "stop.fill" : "play.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.accentPurple)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.surfaceSubtle))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedSoundName = alarmSoundName
        }
        .background(isSelected ? Color.surfaceSelected : Color.surfaceSubtle)
        .contextMenu {
            Button(role: .destructive) {
                pendingDeletion = custom
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Deletion

    private var deleteDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }

    private var deleteDialogTitle: LocalizedStringKey {
        guard let pending = pendingDeletion else { return "Delete Recording?" }
        return "Delete \"\(pending.name)\"?"
    }

    private func deleteDialogMessage(for custom: CustomSound) -> LocalizedStringKey {
        let count = CustomSoundDeletion.alarmsReferencing(custom, in: modelContext).count
        if count == 0 {
            return "This recording will be permanently deleted."
        } else if count == 1 {
            return "1 alarm uses this sound and will switch to \"Lecha Dodi\"."
        } else {
            return "\(count) alarms use this sound and will switch to \"Lecha Dodi\"."
        }
    }

    private func confirmDelete(_ custom: CustomSound) {
        let alarmSoundName = AlarmSound.customSoundName(fileName: custom.fileName)
        if previewingCustomFileName == custom.fileName {
            AudioManager.shared.stopPreview()
            previewingCustomFileName = nil
        }
        // If the deleted sound was also the picker's current selection, fall back.
        if selectedSoundName == alarmSoundName {
            selectedSoundName = AlarmSound.defaultSound.name
        }
        Task {
            await CustomSoundDeletion.delete(custom, in: modelContext)
            pendingDeletion = nil
        }
    }

    private func durationString(_ duration: Double) -> String {
        let total = max(0, duration)
        let seconds = Int(total)
        let tenths = Int((total * 10).truncatingRemainder(dividingBy: 10))
        return String(format: "%d.%ds", seconds, tenths)
    }

    private func stopCustomPreview() {
        if previewingCustomFileName != nil {
            AudioManager.shared.stopPreview()
            previewingCustomFileName = nil
        }
    }
}

// MARK: - Category Section

struct SoundCategorySection: View {
    let category: AlarmSound.Category
    let sounds: [AlarmSound]
    @Binding var selectedSoundName: String
    @Binding var previewingSound: AlarmSound?
    let isPremium: Bool
    let onLockedTap: () -> Void
    let onAnyPreviewTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: category.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(.accentPurple)

                Text(category.displayName)
                    .font(AppFont.body(15))
                    .fontWeight(.semibold)
                    .foregroundStyle(.textPrimary)
            }

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
            onLockedTap()
            return
        }
        selectedSoundName = sound.name
    }

    private func handlePreview(_ sound: AlarmSound) {
        onAnyPreviewTap()
        if previewingSound?.id == sound.id {
            AudioManager.shared.stopPreview()
            previewingSound = nil
        } else {
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
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark" : "")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.accentPurple)
                .frame(width: 16)

            Text(sound.displayName)
                .font(AppFont.body())
                .foregroundColor(isLocked ? .textSecondary.opacity(0.5) : .textPrimary)

            Spacer()

            if isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.goldAccent.opacity(0.7))
            }

            Button(action: onPreview) {
                Image(systemName: isPreviewing ? "stop.fill" : "play.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.accentPurple)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.surfaceSubtle))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .background(isSelected ? Color.surfaceSelected : Color.surfaceSubtle)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SoundPickerView(selectedSoundName: .constant("Lecha Dodi"))
    }
}

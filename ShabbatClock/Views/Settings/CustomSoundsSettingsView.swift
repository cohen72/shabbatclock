import SwiftUI
import SwiftData

/// Management screen for user-recorded alarm sounds.
/// Lists all recordings with duration, creation date, and number of alarms using each.
/// Supports swipe-to-delete and long-press context menu — both confirm before destroying.
struct CustomSoundsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CustomSound.createdAt, order: .reverse) private var customSounds: [CustomSound]
    @ObservedObject private var storeManager = StoreManager.shared

    @State private var showingRecorder = false
    @State private var showingPremium = false
    @State private var previewingFileName: String?
    @State private var pendingDeletion: CustomSound?

    var body: some View {
        ZStack {
            LinearGradient.nightSky
                .ignoresSafeArea()

            if customSounds.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(customSounds) { sound in
                        recordingRow(sound)
                            .listRowBackground(Color.surfaceCard)
                            .listRowSeparatorTint(Color.surfaceBorder)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    pendingDeletion = sound
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    pendingDeletion = sound
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Custom Sounds")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if storeManager.isPremium {
                        showingRecorder = true
                    } else {
                        showingPremium = true
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingRecorder) {
            SoundRecordingView()
        }
        .sheet(isPresented: $showingPremium) {
            PremiumView()
                .applyLanguageOverride(AppLanguage.current)
        }
        .confirmationDialog(
            dialogTitle,
            isPresented: dialogBinding,
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { sound in
            Button("Delete", role: .destructive) {
                performDelete(sound)
            }
            Button("Cancel", role: .cancel) {
                pendingDeletion = nil
            }
        } message: { sound in
            Text(dialogMessage(for: sound))
        }
        .onDisappear {
            AudioManager.shared.stopPreview()
            previewingFileName = nil
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.slash")
                .font(.system(size: 44))
                .foregroundStyle(.textSecondary.opacity(0.5))

            Text("No Recordings Yet")
                .font(AppFont.header(20))
                .foregroundStyle(.textPrimary)

            Text(storeManager.isPremium
                 ? "Tap + to record a custom alarm sound"
                 : "Upgrade to Premium to record custom alarm sounds")
                .font(AppFont.body(14))
                .foregroundStyle(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            if !storeManager.isPremium {
                Button {
                    showingPremium = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 12))
                        Text("Go Premium")
                            .font(AppFont.body(14))
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        Capsule().fill(Color.goldAccent)
                    )
                }
                .padding(.top, 8)
            }
        }
        .padding(.top, 80)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Row

    @ViewBuilder
    private func recordingRow(_ sound: CustomSound) -> some View {
        let isPreviewing = previewingFileName == sound.fileName
        let alarmCount = CustomSoundDeletion.alarmsReferencing(sound, in: modelContext).count

        HStack(spacing: 12) {
            Button {
                togglePreview(sound)
            } label: {
                Image(systemName: isPreviewing ? "stop.fill" : "play.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.accentPurple)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.surfaceSubtle))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(sound.name)
                    .font(AppFont.body(15))
                    .fontWeight(.medium)
                    .foregroundStyle(.textPrimary)

                HStack(spacing: 8) {
                    Text(durationString(sound.duration))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.textSecondary)

                    Text("•")
                        .font(.system(size: 11))
                        .foregroundStyle(.textSecondary.opacity(0.5))

                    Text(dateString(sound.createdAt))
                        .font(AppFont.caption(11))
                        .foregroundStyle(.textSecondary)

                    if alarmCount > 0 {
                        Text("•")
                            .font(.system(size: 11))
                            .foregroundStyle(.textSecondary.opacity(0.5))

                        HStack(spacing: 3) {
                            Image(systemName: "alarm.fill")
                                .font(.system(size: 9))
                            Text(alarmCountLabel(alarmCount))
                                .font(AppFont.caption(11))
                        }
                        .foregroundStyle(.goldAccent)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func togglePreview(_ sound: CustomSound) {
        if previewingFileName == sound.fileName {
            AudioManager.shared.stopPreview()
            previewingFileName = nil
        } else {
            AudioManager.shared.stopPreview()
            AudioManager.shared.playPreview(customFileName: sound.fileName)
            previewingFileName = sound.fileName
            AudioManager.shared.onPreviewStopped = {
                Task { @MainActor in
                    previewingFileName = nil
                }
            }
        }
    }

    // MARK: - Deletion

    private var dialogBinding: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }

    private var dialogTitle: LocalizedStringKey {
        guard let pending = pendingDeletion else { return "Delete Recording?" }
        return "Delete \"\(pending.name)\"?"
    }

    private func dialogMessage(for sound: CustomSound) -> LocalizedStringKey {
        let count = CustomSoundDeletion.alarmsReferencing(sound, in: modelContext).count
        if count == 0 {
            return "This recording will be permanently deleted."
        } else if count == 1 {
            return "1 alarm uses this sound and will switch to \"Lecha Dodi\"."
        } else {
            return "\(count) alarms use this sound and will switch to \"Lecha Dodi\"."
        }
    }

    private func performDelete(_ sound: CustomSound) {
        if previewingFileName == sound.fileName {
            AudioManager.shared.stopPreview()
            previewingFileName = nil
        }
        Task {
            await CustomSoundDeletion.delete(sound, in: modelContext)
            pendingDeletion = nil
        }
    }

    // MARK: - Formatting

    private func durationString(_ duration: Double) -> String {
        let total = max(0, duration)
        let seconds = Int(total)
        let tenths = Int((total * 10).truncatingRemainder(dividingBy: 10))
        return String(format: "%d.%ds", seconds, tenths)
    }

    private func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.current.effectiveLocale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func alarmCountLabel(_ count: Int) -> LocalizedStringKey {
        count == 1 ? "1 alarm" : "\(count) alarms"
    }
}

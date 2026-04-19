import SwiftUI

/// Sound picker view with categories and preview functionality.
struct SoundPickerView: View {
  @Binding var selectedSoundName: String
  
  @State private var previewingSound: AlarmSound?
  @State private var showingPremium = false
  @ObservedObject private var storeManager = StoreManager.shared

  var body: some View {
    ZStack {
      LinearGradient.nightSky
        .ignoresSafeArea()

      ScrollView {
        LazyVStack(spacing: 24) {
          ForEach(AlarmSound.Category.allCases, id: \.self) { category in
            if let sounds = AlarmSound.byCategory[category], !sounds.isEmpty {
              SoundCategorySection(
                category: category,
                sounds: sounds,
                selectedSoundName: $selectedSoundName,
                previewingSound: $previewingSound,
                isPremium: storeManager.isPremium,
                onLockedTap: { showingPremium = true }
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
    .onAppear {
      AudioManager.shared.onPreviewStopped = { [self] in
        previewingSound = nil
      }
    }
    .onDisappear {
      AudioManager.shared.stopPreview()
      AudioManager.shared.onPreviewStopped = nil
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

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      // Category header
      HStack(spacing: 8) {
        Image(systemName: category.icon)
          .font(.system(size: 14))
          .foregroundStyle(.accentPurple)

        Text(category.displayName)
          .font(AppFont.body(15))
          .fontWeight(.semibold)
          .foregroundStyle(.textPrimary)
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
      onLockedTap()
      return
    }
    selectedSoundName = sound.name
  }
  
  private func handlePreview(_ sound: AlarmSound) {
    // Allow preview even for locked sounds — lets users hear what they're missing
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
    HStack(spacing: 12) {
      // Checkmark for selected — fixed width so layout doesn't shift
      Image(systemName: isSelected ? "checkmark" : "")
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(.accentPurple)
        .frame(width: 16)

      // Sound name
      Text(sound.displayName)
        .font(AppFont.body())
        .foregroundColor(isLocked ? .textSecondary.opacity(0.5) : .textPrimary)

      Spacer()

      // Lock icon for premium
      if isLocked {
        Image(systemName: "lock.fill")
          .font(.system(size: 12))
          .foregroundColor(.goldAccent.opacity(0.7))
      }

      // Preview button — always enabled so users can hear premium sounds
      Button(action: onPreview) {
        Image(systemName: isPreviewing ? "stop.fill" : "play.fill")
          .font(.system(size: 12))
          .foregroundStyle(.accentPurple)
          .frame(width: 32, height: 32)
          .background(
            Circle()
              .fill(Color.surfaceSubtle)
          )
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

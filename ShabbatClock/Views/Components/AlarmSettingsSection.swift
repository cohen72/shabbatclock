import SwiftUI

/// Shared alarm settings used by both AlarmEditView and ZmanAlarmSheet.
/// Contains: sound picker, auto-stop duration, label, ring setup education.
struct AlarmSettingsSection: View {
  @Binding var soundName: String
  @Binding var alarmDuration: Int
  @Binding var label: String
  
  @Environment(AlarmKitService.self) private var alarmService
  @Environment(\.modelContext) private var modelContext
  @ObservedObject private var storeManager = StoreManager.shared
  @State private var showingRingSetup = false
  @State private var showingPremium = false
  
  /// The only duration available to free users. Anything longer requires Premium.
  private static let freeDurationSeconds = 60

  private var alarmDurationOptions: [(String, Int)] {
    [
      ("60 sec", 60),
      ("2 min", 120),
      ("3 min", 180),
      ("4 min", 240),
      ("5 min", 300),
    ]
  }

  private func isLocked(_ seconds: Int) -> Bool {
    !storeManager.isPremium && seconds > Self.freeDurationSeconds
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
      // If a previously-premium user is now on free and lands on a gated value,
      // clamp down to the free tier so the saved alarm matches what's allowed.
      if isLocked(alarmDuration) {
        alarmDuration = Self.freeDurationSeconds
      }
    }
    .sheet(isPresented: $showingPremium) {
      PremiumView()
        .applyLanguageOverride(AppLanguage.current)
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
    VStack(alignment: .leading, spacing: 4) {
      Text("Label")
        .font(AppFont.caption(12))
        .foregroundStyle(.textSecondary)
      
      TextField("Alarm", text: $label)
        .font(AppFont.body())
        .foregroundStyle(.textPrimary)
        .multilineTextAlignment(.leading)
        .submitLabel(.done)
        .tint(.accentPurple)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(16)
    .themeCard(cornerRadius: 14)
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

        durationMenu
      }
      .padding(16)
      .themeCard(cornerRadius: 14)
    }
  }
  
  private var durationMenu: some View {
    Menu {
      ForEach(alarmDurationOptions, id: \.1) { option in
        Button {
          if isLocked(option.1) {
            showingPremium = true
          } else {
            alarmDuration = option.1
          }
        } label: {
          if isLocked(option.1) {
            Label(LocalizedStringKey(option.0), systemImage: "lock.fill")
          } else if option.1 == alarmDuration {
            Label(LocalizedStringKey(option.0), systemImage: "checkmark")
          } else {
            Text(LocalizedStringKey(option.0))
          }
        }
      }
    } label: {
      HStack(spacing: 4) {
        Text(LocalizedStringKey(currentDurationLabel))
          .font(AppFont.body())
          .foregroundStyle(.accentPurple)
        Image(systemName: "chevron.up.chevron.down")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.accentPurple)
      }
    }
  }
  
  private var currentDurationLabel: String {
    alarmDurationOptions.first(where: { $0.1 == alarmDuration })?.0
    ?? alarmDurationOptions.last?.0
    ?? ""
  }
  
  // MARK: - Ring Setup Education
  
  /// Important callout in the alarm edit screen warning about the vibration caveat
  /// of the silencer mechanism, with a tap target opening the full RingSetupView walkthrough.
  ///
  /// Layout: icon is inline with the title (not a separate column), giving the
  /// subtitle the full card width to breathe on one line.
  private var ringSetupCard: some View {
    Button {
      showingRingSetup = true
    } label: {
      VStack(alignment: .leading, spacing: 4) {
        // Title row: icon + title inline
        
        HStack(spacing: 8) {
          
          Text("Important: Stop the vibration")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.textPrimary)
          
          Spacer(minLength: 0)
          
          Image(systemName: "exclamationmark.circle.fill")
            .font(.system(size: 18))
            .foregroundStyle(.goldAccent)
          
        }
        
        // Subtitle gets the full width
        Text("For vibration-free auto-stop, turn off Haptics in Settings.")
          .font(.system(size: 11))
          .foregroundStyle(.textSecondary)
          .multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)
        
        Text("Learn how →")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.accentPurple)
          .padding(.top, 2)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
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

#Preview {
  @Previewable @State var soundName = "Lecha Dodi.m4a"
  @Previewable @State var alarmDuration = 15
  @Previewable @State var label = "Morning Alarm"
  
  NavigationStack {
    ScrollView {
      AlarmSettingsSection(
        soundName: $soundName,
        alarmDuration: $alarmDuration,
        label: $label
      )
      .padding()
    }
    .background(Color.backgroundPrimary)
    .navigationTitle("Alarm Settings")
    .navigationBarTitleDisplayMode(.inline)
  }
  .environment(AlarmKitService.shared)
  .modelContainer(for: Alarm.self, inMemory: true)
}


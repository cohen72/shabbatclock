import SwiftUI
import SwiftData

/// View for editing or creating an alarm.
struct AlarmEditView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Environment(AlarmKitService.self) private var alarmService

  let alarm: Alarm
  let isNew: Bool
  
  // Draft state — only written back on Save
  @State private var draftHour: Int = 0
  @State private var draftMinute: Int = 0
  @State private var draftLabel: String = ""
  @State private var draftSoundName: String = ""
  @State private var draftRepeatDays: [Int] = []
  @State private var draftSnoozeEnabled: Bool = false
  @State private var draftSnoozeDuration: Int = 5 * 60
  @State private var draftAlarmDuration: Int = 60

  @State private var showingDeleteConfirmation = false
  @State private var showingAlarmPermission = false
  @State private var showingNotificationPermission = false

  @AppStorage("isPremium") private var isPremium = false
  @AppStorage("defaultSound") private var defaultSound = "Shalom Aleichem"
  @AppStorage("defaultAlarmDuration") private var defaultAlarmDuration = 60
  
  private let snoozeDurationOptions: [(String, Int)] = [
    ("1 min", 60),
    ("3 min", 180),
    ("5 min", 300),
    ("9 min", 540),
    ("10 min", 600),
  ]
  
  var body: some View {
    NavigationStack {
      ZStack {
        LinearGradient.nightSky
          .ignoresSafeArea()
        
        ScrollView {
          VStack(spacing: 16) {
            // Time picker
            timePickerSection
              .padding(.bottom, 8)
            
            // Repeat days
            repeatSection
            
            // Shared alarm settings (label, sound, auto-stop, vibration hint)
            AlarmSettingsSection(
              soundName: $draftSoundName,
              alarmDuration: $draftAlarmDuration,
              label: $draftLabel
            )
            
            // Snooze intentionally hidden — Shabbat clock has no snooze
            
            // Delete button (for existing alarms)
            if !isNew {
              deleteButton
                .padding(.top, 8)
            }
          }
          .padding(.horizontal, 20)
          .padding(.top, 16)
          .padding(.bottom, 40)
        }
      }
      .navigationTitle(isNew ? "New Alarm" : "Edit Alarm")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(role: .close) {
            dismiss()
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            saveAlarm()
          }
          .foregroundStyle(.accentPurple)
          .fontWeight(.bold)
        }
      }
    }
    .onAppear {
      // Always respect the alarm's time — presets set specific hours,
      // and the default Alarm() init uses 7:00 which is a sensible fallback.
      draftHour = alarm.hour
      draftMinute = alarm.minute
      draftLabel = alarm.label
      draftSoundName = isNew ? defaultSound : alarm.soundName
      draftRepeatDays = alarm.repeatDays
      draftSnoozeEnabled = alarm.snoozeEnabled
      draftSnoozeDuration = alarm.snoozeDurationSeconds
      // For new alarms, seed from the user's default (from Settings);
      // for existing, use whatever is persisted on the alarm.
      draftAlarmDuration = isNew ? defaultAlarmDuration : alarm.alarmDurationSeconds
    }
    .scrollDismissesKeyboard(.immediately)
    .alert("Delete Alarm", isPresented: $showingDeleteConfirmation) {
      Button("Cancel", role: .cancel) {}
      Button("Delete", role: .destructive) {
        deleteAlarm()
      }
    } message: {
      Text("Are you sure you want to delete this alarm?")
    }
    .fullScreenCover(isPresented: $showingAlarmPermission) {
      PermissionPromptView.alarms(
        onContinue: {
          showingAlarmPermission = false
          Task {
            await alarmService.requestAuthorization()
            // Save the row regardless — if AlarmKit was denied, the row persists
            // and the in-app banner will prompt the user to enable it in Settings.
            // Once enabled, observeAuthorizationChanges re-schedules automatically.
            if alarmService.isAuthorized && !alarmService.isNotificationAuthorized {
              showingNotificationPermission = true
            } else {
              commitSave()
            }
          }
        }
      )
    }
    .fullScreenCover(isPresented: $showingNotificationPermission) {
      PermissionPromptView.notifications(
        onContinue: {
          showingNotificationPermission = false
          Task {
            await alarmService.requestNotificationAuthorization()
            commitSave()
          }
        }
      )
    }
  }
  
  // MARK: - Time Picker
  
  private var timePickerSection: some View {
    DatePicker(
      "",
      selection: Binding(
        get: {
          Calendar.current.date(from: DateComponents(hour: draftHour, minute: draftMinute)) ?? Date()
        },
        set: { newDate in
          let components = Calendar.current.dateComponents([.hour, .minute], from: newDate)
          draftHour = components.hour ?? 0
          draftMinute = components.minute ?? 0
        }
      ),
      displayedComponents: .hourAndMinute
    )
    .datePickerStyle(.wheel)
    .labelsHidden()
    .frame(height: 160)
    // Time is always read hour → minute → period, regardless of language.
    // Matches the digital clock display on the main screen and Apple's own Clock app.
    .environment(\.layoutDirection, .leftToRight)
    // Honor the user's in-app 12/24h preference. Falls back to the iOS-level
    // 24-Hour Time setting via `.autoupdatingCurrent` when preference is `.system`.
    .environment(\.locale, pickerLocale)
  }

  /// Locale driving the DatePicker's 12/24h hour format.
  ///
  /// Using region-bound locales (`en_US`, `en_GB`) lets DatePicker's `j`-template
  /// hour symbol resolve to the right format — bare `en` / `he` default to 12h,
  /// which is why we can't just reuse the app-language locale here.
  private var pickerLocale: Locale {
    switch TimeFormatter.userPreference {
    case .system: return .autoupdatingCurrent
    case .twelveHour: return Locale(identifier: "en_US")
    case .twentyFourHour: return Locale(identifier: "en_GB")
    }
  }
  
  // MARK: - Repeat Section
  
  private var repeatSection: some View {
    NavigationLink {
      RepeatDaysPickerView(selectedDays: $draftRepeatDays)
    } label: {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text("Repeat")
            .font(AppFont.caption(12))
            .foregroundStyle(.textSecondary)
          
          Text(repeatDaysDisplayString)
            .font(AppFont.body())
            .foregroundStyle(.textPrimary)
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
  
  private var repeatDaysDisplayString: String {
    if draftRepeatDays.isEmpty {
      return String(localized: "One time")
    }
    if draftRepeatDays.count == 7 {
      return String(localized: "Every day")
    }
    if Set(draftRepeatDays) == Set([0, 6]) {
      return String(localized: "Weekends")
    }
    if Set(draftRepeatDays) == Set([1, 2, 3, 4, 5]) {
      return String(localized: "Weekdays")
    }
    let formatter = DateFormatter()
    formatter.locale = AppLanguage.current.effectiveLocale
    let isHebrew = formatter.locale.language.languageCode?.identifier == "he"
    let symbols = (isHebrew ? formatter.veryShortWeekdaySymbols : formatter.shortWeekdaySymbols)
    ?? ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    return draftRepeatDays.sorted().map { symbols[$0] }.joined(separator: ", ")
  }
  
  // MARK: - Snooze Section
  
  private var snoozeSection: some View {
    VStack(spacing: 12) {
      // Snooze toggle
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text("Snooze")
            .font(AppFont.caption(12))
            .foregroundStyle(.textSecondary)
          
          Text(draftSnoozeEnabled ? "Enabled" : "Disabled")
            .font(AppFont.body())
            .foregroundStyle(.textPrimary)
        }
        
        Spacer()
        
        Toggle("", isOn: $draftSnoozeEnabled)
          .labelsHidden()
          .tint(.accentPurple)
      }
      .padding(16)
      .themeCard(cornerRadius: 14)
      
      // Snooze duration picker (shown when snooze enabled)
      if draftSnoozeEnabled {
        HStack {
          Text("Snooze Duration")
            .font(AppFont.body())
            .foregroundStyle(.textPrimary)
          
          Spacer()
          
          Picker("", selection: $draftSnoozeDuration) {
            ForEach(snoozeDurationOptions, id: \.1) { option in
              Text(option.0).tag(option.1)
            }
          }
          .tint(.accentPurple)
        }
        .padding(16)
        .themeCard(cornerRadius: 14)
        .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
    .animation(.easeInOut(duration: 0.2), value: draftSnoozeEnabled)
  }
  
  // MARK: - Delete Button
  
  private var deleteButton: some View {
    Button {
      showingDeleteConfirmation = true
    } label: {
      HStack {
        Image(systemName: "trash")
        Text("Delete Alarm")
      }
      .font(AppFont.body())
      .foregroundStyle(.red)
      .frame(maxWidth: .infinity)
      .padding(16)
      .background(
        RoundedRectangle(cornerRadius: 14)
          .fill(Color.red.opacity(0.1))
          .overlay(
            RoundedRectangle(cornerRadius: 14)
              .stroke(Color.red.opacity(0.15), lineWidth: 0.5)
          )
      )
    }
  }
  
  // MARK: - Actions
  
  private func saveAlarm() {
    // First save: prompt for AlarmKit permission if never asked
    if !alarmService.isAuthorized && !alarmService.hasBeenAskedForAuthorization {
      showingAlarmPermission = true
      return
    }
    
    // If authorized, check notification permission (for auto-stop)
    if alarmService.isAuthorized && !alarmService.isNotificationAuthorized {
      showingNotificationPermission = true
      return
    }
    
    commitSave()
  }
  
  /// Actually save the alarm. If AlarmKit is denied, the row persists but doesn't schedule;
  /// the in-app banner prompts the user to enable it, and syncAllAlarms runs when they do.
  private func commitSave() {
    alarm.hour = draftHour
    alarm.minute = draftMinute
    alarm.label = draftLabel
    alarm.soundName = draftSoundName
    alarm.repeatDays = draftRepeatDays
    // Snooze is disabled app-wide for now — persist false regardless of draft state
    // so no saved alarm carries a legacy-default `true` into the future.
    alarm.snoozeEnabled = false
    alarm.snoozeDurationSeconds = 0
    alarm.isEnabled = true

    // Free tier is capped at 60s auto-stop; longer durations are premium-only.
    if !StoreManager.shared.isPremium && draftAlarmDuration > 60 {
      alarm.alarmDurationSeconds = 60
    } else {
      alarm.alarmDurationSeconds = draftAlarmDuration
    }
    
    if isNew {
      modelContext.insert(alarm)
      Analytics.track(.alarmCreated(
        source: .manual,
        zmanType: nil,
        hasRepeat: !draftRepeatDays.isEmpty,
        repeatDayCount: draftRepeatDays.count,
        soundCategory: AlarmSound.sound(named: draftSoundName)?.category.rawValue ?? "unknown",
        timeBucket: .bucket(hour: draftHour)
      ))
    } else {
      Analytics.track(.alarmEdited(source: .manual))
    }

    Task {
      await alarmService.enable(alarm)
      dismiss()
    }
  }
  
  private func deleteAlarm() {
    let alarmToDelete = alarm
    Analytics.track(.alarmDeleted(source: alarmToDelete.zmanTypeRawValue == nil ? .manual : .zman))
    dismiss()
    DispatchQueue.main.async {
      alarmService.delete(alarmToDelete)
    }
  }
  
  private func openAppSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
  }
}

// MARK: - Preview

#Preview {
  AlarmEditView(
    alarm: Alarm(hour: 7, minute: 30, label: "Shacharis"),
    isNew: true
  )
  .modelContainer(for: Alarm.self, inMemory: true)
  .environment(AlarmKitService.shared)
}

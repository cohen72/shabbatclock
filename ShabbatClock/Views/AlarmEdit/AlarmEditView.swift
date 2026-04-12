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
    @State private var draftSnoozeEnabled: Bool = true
    @State private var draftSnoozeDuration: Int = 5 * 60
    @State private var draftAlarmDuration: Int = 30

    @State private var showingDeleteConfirmation = false
    @State private var showingAlarmPermission = false
    @State private var showingNotificationPermission = false
    @State private var showingFallbackAlert = false

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

                        // Label
                        labelSection

                        // Sound
                        soundSection

                        // Repeat days
                        repeatSection

                        // Alarm duration (auto-stop)
                        alarmDurationSection

                        // Snooze
                        snoozeSection

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
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.textSecondary)
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
            draftHour = alarm.hour
            draftMinute = alarm.minute
            draftLabel = alarm.label
            draftSoundName = alarm.soundName
            draftRepeatDays = alarm.repeatDays
            draftSnoozeEnabled = alarm.snoozeEnabled
            draftSnoozeDuration = alarm.snoozeDurationSeconds
            draftAlarmDuration = alarm.alarmDurationSeconds
        }
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .confirmationDialog("Delete Alarm", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteAlarm()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this alarm?")
        }
        .fullScreenCover(isPresented: $showingAlarmPermission) {
            PermissionPromptView.alarms(
                onContinue: {
                    showingAlarmPermission = false
                    Task {
                        await alarmService.requestAuthorization()
                        if alarmService.isAuthorized {
                            // Full AlarmKit mode — check notification permission next
                            if !alarmService.isNotificationAuthorized {
                                showingNotificationPermission = true
                            } else {
                                commitSave()
                            }
                        } else {
                            // User denied — save with fallback and show info alert
                            commitSave()
                            showingFallbackAlert = true
                        }
                    }
                },
                onSkip: {
                    showingAlarmPermission = false
                    // Save with fallback and show info alert
                    commitSave()
                    showingFallbackAlert = true
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
                },
                onSkip: {
                    showingNotificationPermission = false
                    commitSave()
                }
            )
        }
        .alert("Alarm Saved in Basic Mode", isPresented: $showingFallbackAlert) {
            Button("Open Settings") {
                openAppSettings()
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your alarm will use a 30-second notification sound. To enable full alarm features — longer durations, Do Not Disturb override, and Shabbat mode — allow alarms in Settings.")
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
    }

    // MARK: - Label Section

    private var labelSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Label")
                .font(AppFont.caption(12))
                .foregroundStyle(.textSecondary)
                .padding(.leading, 4)

            TextField("Alarm", text: $draftLabel)
                .font(AppFont.body())
                .foregroundStyle(.textPrimary)
                .submitLabel(.done)
                .padding(16)
                .themeCard(cornerRadius: 14)
                .tint(.accentPurple)
        }
    }

    // MARK: - Sound Section

    private var soundSection: some View {
        NavigationLink {
            SoundPickerView(selectedSoundName: $draftSoundName)
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

                        Text(draftSoundName)
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

    // MARK: - Alarm Duration Section

    private var alarmDurationSection: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Auto-Stop")
                        .font(AppFont.caption(12))
                        .foregroundStyle(.textSecondary)

                    Text("Alarm stops automatically after this duration")
                        .font(.system(size: 11))
                        .foregroundStyle(.textSecondary.opacity(0.6))
                }

                Spacer()

                if alarmService.isFallbackMode {
                    Text("30 sec")
                        .font(AppFont.body())
                        .foregroundStyle(.textSecondary)
                } else {
                    Picker("", selection: $draftAlarmDuration) {
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
                    openAppSettings()
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

    /// Actually save the alarm — uses AlarmKit if authorized, fallback notifications otherwise.
    private func commitSave() {
        alarm.hour = draftHour
        alarm.minute = draftMinute
        alarm.label = draftLabel
        alarm.soundName = draftSoundName
        alarm.repeatDays = draftRepeatDays
        alarm.snoozeEnabled = draftSnoozeEnabled
        alarm.snoozeDurationSeconds = draftSnoozeEnabled ? draftSnoozeDuration : 0
        alarm.isEnabled = true

        if alarmService.isFallbackMode {
            // Fallback: force 30s duration and schedule via notifications
            alarm.alarmDurationSeconds = AlarmKitService.fallbackMaxDuration
        } else {
            alarm.alarmDurationSeconds = draftAlarmDuration
        }

        if isNew {
            modelContext.insert(alarm)
        }

        Task {
            if alarmService.isAuthorized {
                if let newID = await alarmService.scheduleAlarm(for: alarm) {
                    alarm.alarmKitID = newID
                }
            } else {
                alarmService.scheduleFallbackAlarm(for: alarm)
            }
            alarmService.updateNextAlarmDate()
        }

        dismiss()
    }

    private func deleteAlarm() {
        alarmService.cancelAlarm(for: alarm)
        modelContext.delete(alarm)
        alarmService.updateNextAlarmDate()
        dismiss()
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

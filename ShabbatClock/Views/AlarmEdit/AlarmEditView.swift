import SwiftUI
import SwiftData

/// View for editing or creating an alarm.
struct AlarmEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var alarmScheduler: AlarmScheduler

    let alarm: Alarm
    let isNew: Bool

    // Draft state — only written back on Save
    @State private var draftHour: Int = 0
    @State private var draftMinute: Int = 0
    @State private var draftLabel: String = ""
    @State private var draftSoundName: String = ""
    @State private var draftRepeatDays: [Int] = []

    @State private var showingDeleteConfirmation = false

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
        alarm.hour = draftHour
        alarm.minute = draftMinute
        alarm.label = draftLabel
        alarm.soundName = draftSoundName
        alarm.repeatDays = draftRepeatDays
        alarm.isEnabled = true
        if isNew {
            modelContext.insert(alarm)
        }
        alarmScheduler.scheduleNotification(for: alarm)
        alarmScheduler.updateNextAlarmDate()
        dismiss()
    }

    private func deleteAlarm() {
        alarmScheduler.removeNotification(for: alarm)
        modelContext.delete(alarm)
        alarmScheduler.updateNextAlarmDate()
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    AlarmEditView(
        alarm: Alarm(hour: 7, minute: 30, label: "Shacharis"),
        isNew: true
    )
    .modelContainer(for: Alarm.self, inMemory: true)
    .environmentObject(AlarmScheduler.shared)
}

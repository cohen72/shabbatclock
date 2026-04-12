import SwiftUI
import SwiftData

/// View for editing or creating an alarm.
struct AlarmEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var alarmScheduler: AlarmScheduler

    @Bindable var alarm: Alarm
    let isNew: Bool

    @State private var showingDeleteConfirmation = false
    @State private var showingSoundPicker = false
    @State private var showingRepeatPicker = false

    var body: some View {
        ZStack {
            LinearGradient.nightSky
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                headerView

                ScrollView {
                    VStack(spacing: 16) {
                        // Time picker
                        timePickerSection
                            .padding(.bottom, 8)

                        // Label
                        labelSection

                        // Sound
                        InlineSoundPicker(selectedSoundName: $alarm.soundName)

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
        }
        .sheet(isPresented: $showingSoundPicker) {
            SoundPickerView(selectedSoundName: $alarm.soundName)
        }
        .sheet(isPresented: $showingRepeatPicker) {
            RepeatDaysPickerView(selectedDays: $alarm.repeatDays)
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

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .foregroundStyle(.textSecondary)

            Spacer()

            Text(isNew ? "New Alarm" : "Edit Alarm")
                .font(AppFont.header(18))
                .foregroundStyle(.textPrimary)

            Spacer()

            Button("Save") {
                saveAlarm()
            }
            .foregroundStyle(.accentPurple)
            .fontWeight(.bold)
        }
        .padding()
    }

    // MARK: - Time Picker

    private var timePickerSection: some View {
        DatePicker(
            "",
            selection: Binding(
                get: {
                    Calendar.current.date(from: DateComponents(hour: alarm.hour, minute: alarm.minute)) ?? Date()
                },
                set: { newDate in
                    let components = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                    alarm.hour = components.hour ?? 0
                    alarm.minute = components.minute ?? 0
                }
            ),
            displayedComponents: .hourAndMinute
        )
        .datePickerStyle(.wheel)
        .labelsHidden()
        .frame(height: 160)
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Label Section

    private var labelSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Label")
                .font(AppFont.caption(12))
                .foregroundStyle(.textSecondary)
                .padding(.leading, 4)

            TextField("Alarm", text: $alarm.label)
                .font(AppFont.body())
                .foregroundStyle(.textPrimary)
                .submitLabel(.done)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.07))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                        )
                )
                .tint(.accentPurple)
        }
    }

    // MARK: - Repeat Section

    private var repeatSection: some View {
        Button {
            showingRepeatPicker = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Repeat")
                        .font(AppFont.caption(12))
                        .foregroundStyle(.textSecondary)

                    Text(alarm.repeatDaysString)
                        .font(AppFont.body())
                        .foregroundStyle(.textPrimary)
                }

                Spacer()

                if !alarm.repeatDays.isEmpty {
                    HStack(spacing: 4) {
                        ForEach([0, 1, 2, 3, 4, 5, 6], id: \.self) { day in
                            Circle()
                                .fill(alarm.repeatDays.contains(day) ?
                                      Color.goldAccent : Color.white.opacity(0.15))
                                .frame(width: 6, height: 6)
                        }
                    }
                }

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

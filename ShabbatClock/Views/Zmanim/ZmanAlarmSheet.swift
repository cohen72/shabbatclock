import SwiftUI
import SwiftData

/// Unified sheet for creating and managing a zman-linked alarm.
///
/// Opens from the bell icon in ZmanimView or from tapping a zman alarm in AlarmListView.
/// - If no alarm exists: toggle is OFF, settings disabled, flipping ON creates the alarm.
/// - If alarm exists: toggle reflects state, settings active, "Remove Alarm" at bottom.
struct ZmanAlarmSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AlarmKitService.self) private var alarmService

    let zman: ZmanimService.Zman

    /// Existing alarm linked to this zman, or nil if creating new.
    let existingAlarm: Alarm?

    let onDelete: (() -> Void)?

    // Draft state
    @State private var minutesBefore: Int
    @State private var draftSoundName: String
    @State private var draftAlarmDuration: Int
    @State private var draftLabel: String
    @State private var hasChanges = false

    @State private var showingDeleteConfirmation = false
    @State private var showingAlarmPermission = false
    @State private var showingNotificationPermission = false

    @AppStorage("isPremium") private var isPremium = false

    init(
        zman: ZmanimService.Zman,
        existingAlarm: Alarm?,
        onDelete: (() -> Void)? = nil
    ) {
        self.zman = zman
        self.existingAlarm = existingAlarm
        self.onDelete = onDelete

        let alarm = existingAlarm
        _minutesBefore = State(initialValue: alarm?.zmanMinutesBefore ?? 0)
        let fallbackSound = UserDefaults.standard.string(forKey: "defaultSound") ?? "Lecha Dodi"
        _draftSoundName = State(initialValue: alarm?.soundName ?? fallbackSound)
        _draftAlarmDuration = State(initialValue: alarm?.alarmDurationSeconds ?? 30)
        _draftLabel = State(initialValue: alarm?.label ?? zman.englishName)
    }

    /// The computed ring time based on current offset selection.
    private var computedFireTime: Date {
        zman.time.addingTimeInterval(-Double(minutesBefore * 60))
    }

    private var fireTimeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        return formatter.string(from: computedFireTime)
    }

    private var firePeriodString: String {
        Calendar.current.component(.hour, from: computedFireTime) < 12 ? "AM" : "PM"
    }

    private var zmanTimeString: String {
        zman.timeString
    }

    private var fireRelativeDay: String {
        let calendar = Calendar.current
        if computedFireTime > Date() && calendar.isDateInToday(computedFireTime) {
            return String(localized: "Today")
        }
        return String(localized: "Tomorrow")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient.nightSky
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // Auto-stop background reminder
                        AutoStopBackgroundBanner()
                            .padding(.top, 12)

                        // Hero card: zman identity
                        heroHeader

                        // Offset picker + fire time
                        offsetCard

                        // Alarm settings (sound, auto-stop, label)
                        AlarmSettingsSection(
                            soundName: $draftSoundName,
                            alarmDuration: $draftAlarmDuration,
                            label: $draftLabel
                        )

                        // Remove button (existing alarms only)
                        if existingAlarm != nil {
                            removeButton
                                .padding(.top, 8)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    // New alarm: always show Save. Existing: show when changes made.
                    if existingAlarm == nil || hasChanges {
                        Button("Save") {
                            saveAlarm()
                        }
                        .foregroundStyle(.accentPurple)
                        .fontWeight(.bold)
                    }
                }
            }
        }
        .onChange(of: minutesBefore) { _, _ in hasChanges = true }
        .onChange(of: draftSoundName) { _, _ in hasChanges = true }
        .onChange(of: draftAlarmDuration) { _, _ in hasChanges = true }
        .onChange(of: draftLabel) { _, _ in hasChanges = true }
        .confirmationDialog("Remove Alarm", isPresented: $showingDeleteConfirmation) {
            Button("Remove", role: .destructive) {
                dismiss()
                onDelete?()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the alarm for this zman.")
        }
        .fullScreenCover(isPresented: $showingAlarmPermission) {
            PermissionPromptView.alarms(
                onContinue: {
                    showingAlarmPermission = false
                    Task {
                        await alarmService.requestAuthorization()
                        if alarmService.isAuthorized && !alarmService.isNotificationAuthorized {
                            showingNotificationPermission = true
                        } else {
                            commitSave()
                        }
                    }
                },
                onSkip: {
                    showingAlarmPermission = false
                    commitSave()
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
    }

    // MARK: - Hero Header

    private var heroHeader: some View {
        VStack(spacing: 4) {
            Text(zman.hebrewName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.goldAccent)

            Text(zman.englishName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.textPrimary)

            Text(zmanTimeString)
                .font(.system(size: 13))
                .foregroundStyle(.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .themeCard(cornerRadius: 14)
    }

    // MARK: - Offset Card

    /// Combined offset picker + computed fire time in one card.
    private var offsetCard: some View {
        VStack(spacing: 0) {
            // Offset picker
            VStack(alignment: .leading, spacing: 8) {
                Text(offsetLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.textSecondary)
                    .padding(.leading, 4)

                Picker("Minutes before", selection: $minutesBefore) {
                    Text("At time").tag(0)
                    Text("5 min").tag(5)
                    Text("10 min").tag(10)
                    Text("15 min").tag(15)
                    Text("30 min").tag(30)
                }
                .pickerStyle(.segmented)
                .colorScheme(.dark)
            }
            .padding(16)

            Divider().overlay(Color.surfaceBorder)

            // Fire time result
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Alarm will ring at")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.textSecondary)

                    Text(fireRelativeDay)
                        .font(.system(size: 11))
                        .foregroundStyle(.textSecondary.opacity(0.7))
                }

                Spacer()

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(fireTimeString)
                        .font(.system(size: 42, weight: .thin, design: .default))
                        .monospacedDigit()
                        .foregroundStyle(.textPrimary)

                    Text(firePeriodString)
                        .font(.system(size: 18, weight: .thin, design: .default))
                        .foregroundStyle(.textSecondary.opacity(0.8))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .themeCard(cornerRadius: 14)
    }

    /// Dynamic label: "Ring at [zman] time" or "Ring before [zman]"
    private var offsetLabel: String {
        let name = AppLanguage.current == .hebrew ? zman.hebrewName : zman.englishName
        if minutesBefore == 0 {
            return String(format: AppLanguage.localized("Ring at %@ time"), name)
        } else {
            return String(format: AppLanguage.localized("Ring before %@"), name)
        }
    }

    // MARK: - Remove Button

    private var removeButton: some View {
        Button {
            showingDeleteConfirmation = true
        } label: {
            HStack {
                Image(systemName: "trash")
                Text("Remove Alarm")
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

    // MARK: - Save

    private func saveAlarm() {
        if !alarmService.isAuthorized && !alarmService.hasBeenAskedForAuthorization {
            showingAlarmPermission = true
            return
        }

        if alarmService.isAuthorized && !alarmService.isNotificationAuthorized {
            showingNotificationPermission = true
            return
        }

        commitSave()
    }

    private func commitSave() {
        let alarm: Alarm
        let isNew: Bool

        if let existing = existingAlarm {
            alarm = existing
            isNew = false
        } else {
            alarm = Alarm()
            isNew = true
        }

        let fireTime = computedFireTime
        let calendar = Calendar.current
        alarm.hour = calendar.component(.hour, from: fireTime)
        alarm.minute = calendar.component(.minute, from: fireTime)
        alarm.isEnabled = true
        alarm.label = draftLabel
        alarm.soundName = draftSoundName
        alarm.snoozeEnabled = false
        alarm.zmanTypeRawValue = zman.type.rawValue
        alarm.zmanMinutesBefore = minutesBefore

        if alarmService.isFallbackMode {
            alarm.alarmDurationSeconds = AlarmKitService.fallbackMaxDuration
        } else {
            alarm.alarmDurationSeconds = draftAlarmDuration
        }

        if isNew {
            modelContext.insert(alarm)
        }

        Task {
            await alarmService.enable(alarm)
            dismiss()
        }
    }
}

// MARK: - Preview

#Preview {
    let zman = ZmanimService.Zman(
        type: .alotHashachar,
        time: Date().addingTimeInterval(3600),
        hebrewName: "עלות השחר",
        englishName: "Dawn",
        description: "72 minutes before sunrise"
    )
    ZmanAlarmSheet(zman: zman, existingAlarm: nil)
        .modelContainer(for: Alarm.self, inMemory: true)
        .environment(AlarmKitService.shared)
}

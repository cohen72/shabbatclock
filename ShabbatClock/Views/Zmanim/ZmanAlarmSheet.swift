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

    #if DEBUG
    /// When set, overrides computedFireTime with this date (debug builds only).
    @State private var debugFireTimeOverride: Date? = nil
    #endif

    @AppStorage("isPremium") private var isPremium = false

    init(
        zman: ZmanimService.Zman,
        existingAlarm: Alarm?,
        onDelete: (() -> Void)? = nil,
        initialMinutesBefore: Int? = nil,
        initialLabel: String? = nil
    ) {
        self.zman = zman
        self.existingAlarm = existingAlarm
        self.onDelete = onDelete

        let alarm = existingAlarm
        _minutesBefore = State(initialValue: alarm?.zmanMinutesBefore ?? initialMinutesBefore ?? 0)
        let fallbackSound = UserDefaults.standard.string(forKey: "defaultSound") ?? "Lecha Dodi"
        _draftSoundName = State(initialValue: alarm?.soundName ?? fallbackSound)
        let defaultDuration = UserDefaults.standard.object(forKey: "defaultAlarmDuration") as? Int ?? 15
        _draftAlarmDuration = State(initialValue: alarm?.alarmDurationSeconds ?? defaultDuration)
        _draftLabel = State(initialValue: alarm?.label ?? initialLabel ?? zman.englishName)
    }

    /// The computed ring time based on current offset selection.
    private var computedFireTime: Date {
        #if DEBUG
        if let override = debugFireTimeOverride { return override }
        #endif
        return zman.time.addingTimeInterval(-Double(minutesBefore * 60))
    }

    private var fireTimeString: String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.current.effectiveLocale
        formatter.dateFormat = "h:mm"
        return formatter.string(from: computedFireTime)
    }

    private var firePeriodString: String {
        Calendar.current.component(.hour, from: computedFireTime) < 12 ? "AM" : "PM"
    }

    private var zmanTimeString: String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.current.effectiveLocale
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: zman.time)
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

                        // Arc showing where this zman falls in the day
                        ZmanArcCard(zman: zman, zmanTimeString: zmanTimeString)

                        // Offset picker + fire time
                        offsetCard

                        // Alarm settings (sound, auto-stop, label)
                        AlarmSettingsSection(
                            soundName: $draftSoundName,
                            alarmDuration: $draftAlarmDuration,
                            label: $draftLabel
                        )

                        #if DEBUG
//                        debugOverrideCard
                        #endif

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
            .navigationTitle("Zman Alarm")
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
        .alert("Remove Alarm", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                dismiss()
                onDelete?()
            }
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
            }
            .padding(16)

            // Fire time row only appears when offset > 0 (otherwise it duplicates the zman time shown above)
            if minutesBefore > 0 {
                Divider().overlay(Color.surfaceBorder)

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
                            .font(.system(size: 26, weight: .thin, design: .default))
                            .monospacedDigit()
                            .foregroundStyle(.textPrimary)

                        Text(firePeriodString)
                            .font(.system(size: 13, weight: .thin, design: .default))
                            .foregroundStyle(.textSecondary.opacity(0.8))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .themeCard(cornerRadius: 14)
        .animation(.easeInOut(duration: 0.2), value: minutesBefore)
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

    // MARK: - Debug Override (DEBUG only)

    #if DEBUG
    private var debugOverrideCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DEBUG")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.orange)
                .padding(.leading, 4)

            VStack(spacing: 8) {
                HStack {
                    Text("Override fire time")
                        .font(.system(size: 13))
                        .foregroundStyle(.textPrimary)
                    Spacer()
                    if let override = debugFireTimeOverride {
                        let f = DateFormatter()
                        let _ = (f.dateFormat = "h:mm:ss a")
                        Text(f.string(from: override))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.orange)
                    } else {
                        Text("Off")
                            .font(.system(size: 12))
                            .foregroundStyle(.textSecondary)
                    }
                }

                HStack(spacing: 8) {
                    debugTimeButton("+30s", seconds: 30)
                    debugTimeButton("+1m", seconds: 60)
                    debugTimeButton("+2m", seconds: 120)
                    debugTimeButton("+5m", seconds: 300)
                    Button("Clear") {
                        debugFireTimeOverride = nil
                        hasChanges = true
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.textSecondary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.orange.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.orange.opacity(0.3), lineWidth: 0.5)
                    )
            )
        }
    }

    private func debugTimeButton(_ title: String, seconds: Int) -> some View {
        Button(title) {
            debugFireTimeOverride = Date().addingTimeInterval(TimeInterval(seconds))
            hasChanges = true
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.orange)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(Color.orange.opacity(0.15))
        )
    }
    #endif

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

        #if DEBUG
        if debugFireTimeOverride != nil {
            ZmanAlarmSyncService.shared.debugSyncSkipIDs.insert(alarm.id)
        }
        #endif

        if alarmService.isFallbackMode {
            alarm.alarmDurationSeconds = AlarmKitService.fallbackMaxDuration
        } else if !StoreManager.shared.isPremium && draftAlarmDuration > 15 {
            // Free tier caps auto-stop at 15s; longer durations are premium-only.
            alarm.alarmDurationSeconds = 15
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

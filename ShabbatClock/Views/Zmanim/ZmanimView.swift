import SwiftUI
import SwiftData

/// View displaying today's Zmanim (halachic times) with one-tap alarm management.
struct ZmanimView: View {
    @StateObject private var zmanimService = ZmanimService.shared
    @StateObject private var locationManager = LocationManager.shared
    @Query(sort: \Alarm.hour) private var allAlarms: [Alarm]

    @State private var showingCreateSheet = false
    @State private var showingManageSheet = false
    @State private var showingCitySearch = false
    @State private var showingLocationPrompt = false
    @State private var showingPremiumAlert = false
    @State private var selectedZman: ZmanimService.Zman?

    // Premium
    private let freeAlarmLimit = 3
    @AppStorage("isPremium") private var isPremium = false

    /// Lookup: zmanType rawValue → linked Alarm
    private var alarmsByZmanType: [String: Alarm] {
        Dictionary(
            allAlarms.compactMap { alarm in
                guard let raw = alarm.zmanTypeRawValue else { return nil }
                return (raw, alarm)
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private var canAddAlarm: Bool {
        isPremium || allAlarms.count < freeAlarmLimit
    }

    // Section definitions
    private enum ZmanSection: String, CaseIterable {
        case morning, afternoon, evening

        var localizedTitle: LocalizedStringKey {
            switch self {
            case .morning: return "Morning"
            case .afternoon: return "Afternoon"
            case .evening: return "Evening"
            }
        }

        var types: Set<ZmanimService.ZmanType> {
            switch self {
            case .morning: return [.alotHashachar, .misheyakir, .netz, .sofZmanShma, .sofZmanTefila]
            case .afternoon: return [.chatzot, .minchaGedola, .minchaKetana, .plagHamincha]
            case .evening: return [.shkia, .tzeitHakochavim]
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient.nightSky
                    .ignoresSafeArea()

                if zmanimService.isLoading {
                    loadingView
                } else if zmanimService.todayZmanim.isEmpty {
                    emptyView
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            locationInfoView
                                .padding(.horizontal, 24)
                                .padding(.bottom, 8)

                            let nextZmanId = zmanimService.todayZmanim.first(where: { $0.time > Date() })?.id

                            ForEach(ZmanSection.allCases, id: \.self) { section in
                                let sectionZmanim = zmanimService.todayZmanim.filter { section.types.contains($0.type) }
                                if !sectionZmanim.isEmpty {
                                    sectionHeader(section.localizedTitle)

                                    LazyVStack(spacing: 6) {
                                        ForEach(sectionZmanim) { zman in
                                            let linkedAlarm = alarmsByZmanType[zman.type.rawValue]
                                            ZmanRowView(
                                                zman: zman,
                                                isNext: zman.id == nextZmanId,
                                                isPast: zman.time <= Date(),
                                                linkedAlarm: linkedAlarm,
                                                onBellTap: {
                                                    handleBellTap(for: zman, existingAlarm: linkedAlarm)
                                                }
                                            )
                                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                                if linkedAlarm != nil {
                                                    Button(role: .destructive) {
                                                        deleteAlarm(for: zman)
                                                    } label: {
                                                        Label("Delete", systemImage: "trash")
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                }
                            }
                        }
                        .padding(.bottom, 120)
                    }
                    .refreshable {
                        if !locationManager.isUsingManualLocation {
                            locationManager.requestLocation()
                        }
                        zmanimService.calculateTodayZmanim()
                    }
                }
            }
            .navigationTitle("Zmanim")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingCitySearch = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 10))
                            if locationManager.locationName == "__unknown__" {
                                Text("Unknown Location")
                                    .font(.system(size: 13, weight: .medium))
                            } else {
                                Text(locationManager.locationName)
                                    .font(.system(size: 13, weight: .medium))
                            }
                        }
                        .foregroundStyle(.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .sheet(isPresented: $showingCitySearch) {
                CitySearchView()
                    .applyLanguageOverride(AppLanguage.current)
            }
        }
        .onAppear {
            if zmanimService.todayZmanim.isEmpty {
                if locationManager.isAuthorized && !locationManager.isUsingManualLocation {
                    locationManager.requestLocation()
                }
                zmanimService.calculateTodayZmanim()
            }
        }
        .onChange(of: locationManager.location) { _, _ in
            zmanimService.calculateTodayZmanim()
        }
        .sheet(isPresented: $showingCreateSheet) {
            if let zman = selectedZman {
                CreateAlarmFromZmanSheet(zman: zman)
                    .applyLanguageOverride(AppLanguage.current)
            }
        }
        .sheet(isPresented: $showingManageSheet) {
            if let zman = selectedZman, let alarm = alarmsByZmanType[zman.type.rawValue] {
                ZmanAlarmSheet(zman: zman, alarm: alarm, onDelete: {
                    deleteAlarm(for: zman)
                })
                .applyLanguageOverride(AppLanguage.current)
            }
        }
        .alert("Upgrade to Premium", isPresented: $showingPremiumAlert) {
            Button("Maybe Later", role: .cancel) {}
            Button("Upgrade") {}
        } message: {
            Text("Free users can create up to \(freeAlarmLimit) alarms. Upgrade to Premium for unlimited alarms and more sounds!")
        }
        .fullScreenCover(isPresented: $showingLocationPrompt) {
            PermissionPromptView.location(
                onContinue: {
                    showingLocationPrompt = false
                    locationManager.requestPermission()
                },
                onSkip: {
                    showingLocationPrompt = false
                }
            )
        }
    }

    // MARK: - Bell Tap Handler

    private func handleBellTap(for zman: ZmanimService.Zman, existingAlarm: Alarm?) {
        selectedZman = zman
        if existingAlarm != nil {
            showingManageSheet = true
        } else {
            if canAddAlarm {
                showingCreateSheet = true
            } else {
                showingPremiumAlert = true
            }
        }
    }

    private func deleteAlarm(for zman: ZmanimService.Zman) {
        guard let alarm = alarmsByZmanType[zman.type.rawValue] else { return }
        AlarmKitService.shared.delete(alarm)
    }

    // MARK: - Subviews

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.textSecondary.opacity(0.6))
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 12)
    }

    private var locationInfoView: some View {
        Text(dateString)
            .font(AppFont.caption(12))
            .foregroundStyle(.textSecondary.opacity(0.7))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .tint(.accentPurple)
            Text("Calculating zmanim...")
                .font(AppFont.body(14))
                .foregroundStyle(.textSecondary)
            Spacer()
        }
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "location.slash")
                .font(.system(size: 48))
                .foregroundStyle(.textSecondary.opacity(0.5))

            Text("Location Required")
                .font(AppFont.header(18))
                .foregroundStyle(.textPrimary)

            Text("Enable location to see\ntoday's zmanim")
                .font(AppFont.body(14))
                .foregroundStyle(.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                showingLocationPrompt = true
            } label: {
                Text("Enable Location")
                    .font(AppFont.body(14))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(Color.accentPurple)
                    )
            }
            .padding(.top, 8)

            Spacer()
        }
    }

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.current.effectiveLocale
        formatter.dateStyle = .full
        return formatter.string(from: Date())
    }
}

// MARK: - Zman Row

struct ZmanRowView: View {
    let zman: ZmanimService.Zman
    var isNext: Bool = false
    var isPast: Bool = false
    let linkedAlarm: Alarm?
    let onBellTap: () -> Void

    @State private var showingInfo = false

    private var bellIconName: String {
        guard let alarm = linkedAlarm else { return "bell" }
        return alarm.isEnabled ? "bell.fill" : "bell.slash"
    }

    private var bellColor: Color {
        guard let alarm = linkedAlarm else { return .textSecondary.opacity(0.4) }
        return alarm.isEnabled ? .accentPurple : .textSecondary.opacity(0.5)
    }

    private var bellBackground: Color {
        guard let alarm = linkedAlarm else { return .surfaceSubtle }
        return alarm.isEnabled ? Color.accentPurple.opacity(0.15) : .surfaceSubtle
    }

    private var alarmSubtitle: String? {
        guard let alarm = linkedAlarm, let minutes = alarm.zmanMinutesBefore else { return nil }
        if minutes == 0 {
            return AppLanguage.localized("At zman time")
        }
        return String(format: AppLanguage.localized("%d min before"), minutes)
    }

    /// Countdown string for the next zman (e.g., "in 47 min")
    private var countdownString: String? {
        guard isNext else { return nil }
        let remaining = Int(zman.time.timeIntervalSince(Date()) / 60)
        guard remaining > 0 else { return nil }
        if remaining >= 60 {
            let hours = remaining / 60
            let mins = remaining % 60
            if mins == 0 {
                return String(format: AppLanguage.localized("in %dh"), hours)
            }
            return String(format: AppLanguage.localized("in %dh %dm"), hours, mins)
        }
        return String(format: AppLanguage.localized("in %d min"), remaining)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Gold accent bar for "next" zman
            if isNext {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.goldAccent)
                    .frame(width: 3)
            }

            // Left: Names + alarm subtitle
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(zman.hebrewName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.goldAccent)
                        .lineLimit(1)

                    if isNext {
                        Text("Next")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.goldAccent)
                            )
                    }
                }

                Text(zman.englishName)
                    .font(.system(size: 12))
                    .foregroundStyle(.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if let subtitle = alarmSubtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.textSecondary.opacity(0.7))
                }
            }

            Spacer()

            // Right: Time + countdown
            VStack(alignment: .trailing, spacing: 2) {
                Text(zman.timeString)
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.textPrimary)

                if let countdown = countdownString {
                    Text(countdown)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.goldAccent)
                }
            }

            // Bell button
            Button(action: onBellTap) {
                Image(systemName: bellIconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(bellColor)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(bellBackground)
                            .overlay(
                                Circle()
                                    .stroke(linkedAlarm?.isEnabled == true
                                            ? Color.accentPurple.opacity(0.4)
                                            : Color.surfaceBorder,
                                            lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.surfaceCard)
                .overlay(
                    isNext ?
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.goldAccent.opacity(0.2), lineWidth: 1) : nil
                )
        )
        .onTapGesture {
            showingInfo = true
        }
        .sheet(isPresented: $showingInfo) {
            ZmanInfoSheet(zman: zman)
                .applyLanguageOverride(AppLanguage.current)
        }
    }
}

// MARK: - Zman Info Sheet

struct ZmanInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let zman: ZmanimService.Zman

    var body: some View {
        ZStack {
            LinearGradient.nightSky
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Handle
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.textSecondary.opacity(0.4))
                    .frame(width: 40, height: 4)
                    .padding(.top, 12)

                VStack(spacing: 8) {
                    Text(zman.hebrewName)
                        .font(.system(size: 28))
                        .foregroundStyle(.goldAccent)

                    Text(zman.englishName)
                        .font(AppFont.header(22))
                        .foregroundStyle(.textPrimary)

                    Text(zman.timeString)
                        .font(AppFont.timeDisplay(48))
                        .foregroundStyle(.textPrimary)
                }

                Text(zman.description)
                    .font(AppFont.body())
                    .foregroundStyle(.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer()
            }
        }
        .presentationDetents([.height(300)])
    }
}

// MARK: - Zman Alarm Management Sheet

struct ZmanAlarmSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AlarmKitService.self) private var alarmService

    let zman: ZmanimService.Zman
    @Bindable var alarm: Alarm
    let onDelete: () -> Void

    @State private var minutesBefore: Int

    init(zman: ZmanimService.Zman, alarm: Alarm, onDelete: @escaping () -> Void) {
        self.zman = zman
        self.alarm = alarm
        self.onDelete = onDelete
        self._minutesBefore = State(initialValue: alarm.zmanMinutesBefore ?? 0)
    }

    var body: some View {
        ZStack {
            LinearGradient.nightSky
                .ignoresSafeArea()

            VStack(spacing: 20) {
                // Handle
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.textSecondary.opacity(0.4))
                    .frame(width: 40, height: 4)
                    .padding(.top, 12)

                // Zman name
                VStack(spacing: 4) {
                    Text(zman.hebrewName)
                        .font(.system(size: 22))
                        .foregroundStyle(.goldAccent)
                    Text(zman.englishName)
                        .font(AppFont.header(18))
                        .foregroundStyle(.textPrimary)
                }

                // Enable/disable toggle
                HStack {
                    Text("Alarm Enabled")
                        .font(AppFont.body(15))
                        .foregroundStyle(.textPrimary)
                    Spacer()
                    Toggle("", isOn: $alarm.isEnabled)
                        .labelsHidden()
                        .tint(.accentPurple)
                        .onChange(of: alarm.isEnabled) { _, newValue in
                            Task {
                                if newValue {
                                    await alarmService.enable(alarm)
                                } else {
                                    alarmService.disable(alarm)
                                }
                            }
                        }
                }
                .padding(.horizontal, 24)

                // Offset picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Wake up before")
                        .font(AppFont.caption(12))
                        .foregroundStyle(.textSecondary)

                    Picker("Minutes before", selection: $minutesBefore) {
                        Text("At time").tag(0)
                        Text("5 min").tag(5)
                        Text("10 min").tag(10)
                        Text("15 min").tag(15)
                        Text("30 min").tag(30)
                    }
                    .pickerStyle(.segmented)
                    .colorScheme(.dark)
                    .onChange(of: minutesBefore) { _, newValue in
                        updateAlarmOffset(to: newValue)
                    }
                }
                .padding(.horizontal, 24)

                // Resulting alarm time
                VStack(spacing: 4) {
                    Text("Alarm will ring at")
                        .font(AppFont.caption(12))
                        .foregroundStyle(.textSecondary)
                    Text(alarmTimeString)
                        .font(AppFont.timeDisplay(32))
                        .foregroundStyle(.goldAccent)
                }

                Spacer()

                // Delete button
                Button(role: .destructive) {
                    dismiss()
                    onDelete()
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("Delete Alarm")
                    }
                    .font(AppFont.body(15))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.red.opacity(0.1))
                    )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
        .presentationDetents([.height(380)])
    }

    private var alarmTimeString: String {
        let alarmTime = zman.time.addingTimeInterval(-Double(minutesBefore * 60))
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: alarmTime)
    }

    private func updateAlarmOffset(to newMinutes: Int) {
        let alarmTime = zman.time.addingTimeInterval(-Double(newMinutes * 60))
        let calendar = Calendar.current
        alarm.hour = calendar.component(.hour, from: alarmTime)
        alarm.minute = calendar.component(.minute, from: alarmTime)
        alarm.zmanMinutesBefore = newMinutes

        Task {
            if alarm.isEnabled {
                await alarmService.enable(alarm)
            } else {
                alarmService.disable(alarm)
            }
        }
    }
}

// MARK: - Create Alarm from Zman Sheet

struct CreateAlarmFromZmanSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AlarmKitService.self) private var alarmService

    let zman: ZmanimService.Zman

    @State private var minutesBefore: Int = 0

    var body: some View {
        ZStack {
            LinearGradient.nightSky
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(.textSecondary)

                    Spacer()

                    Text("Set Alarm")
                        .font(AppFont.header(18))
                        .foregroundStyle(.textPrimary)

                    Spacer()

                    // Invisible spacer to center title
                    Text("Cancel").opacity(0)
                }
                .padding()

                // Zman info
                VStack(spacing: 8) {
                    Text(zman.hebrewName)
                        .font(.system(size: 22))
                        .foregroundStyle(.goldAccent)
                    Text(zman.englishName)
                        .font(AppFont.header(18))
                        .foregroundStyle(.textPrimary)
                    Text(zman.timeString)
                        .font(AppFont.body())
                        .foregroundStyle(.textSecondary)
                }
                .padding(.bottom, 24)

                // Minutes before picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Wake up before")
                        .font(AppFont.caption(12))
                        .foregroundStyle(.textSecondary)

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
                .padding(.horizontal, 24)

                // Resulting alarm time
                VStack(spacing: 4) {
                    Text("Alarm will ring at")
                        .font(AppFont.caption(12))
                        .foregroundStyle(.textSecondary)

                    Text(alarmTimeString)
                        .font(AppFont.timeDisplay(36))
                        .foregroundStyle(.goldAccent)
                }
                .padding(.top, 24)

                Spacer()

                // Save button
                Button {
                    createAlarm()
                } label: {
                    Text("Save Alarm")
                        .font(AppFont.body(16))
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.accentPurple)
                        )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .presentationDetents([.medium])
    }

    private var alarmTimeString: String {
        let alarmTime = zman.time.addingTimeInterval(-Double(minutesBefore * 60))
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: alarmTime)
    }

    private func createAlarm() {
        let alarmTime = zman.time.addingTimeInterval(-Double(minutesBefore * 60))
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: alarmTime)
        let minute = calendar.component(.minute, from: alarmTime)

        let alarm = Alarm(
            hour: hour,
            minute: minute,
            isEnabled: true,
            label: zman.englishName
        )
        alarm.zmanTypeRawValue = zman.type.rawValue
        alarm.zmanMinutesBefore = minutesBefore

        modelContext.insert(alarm)
        Task {
            await alarmService.enable(alarm)
        }

        dismiss()
    }
}

// MARK: - Preview

#Preview {
    ZmanimView()
        .modelContainer(for: Alarm.self, inMemory: true)
        .environment(AlarmKitService.shared)
}

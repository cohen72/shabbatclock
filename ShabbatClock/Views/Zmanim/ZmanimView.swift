import SwiftUI
import SwiftData

/// View displaying today's or tomorrow's Zmanim (halachic times) with one-tap alarm management.
struct ZmanimView: View {
    @StateObject private var zmanimService = ZmanimService.shared
    @StateObject private var locationManager = LocationManager.shared
    @Query(sort: \Alarm.hour) private var allAlarms: [Alarm]

    @State private var showingCitySearch = false
    @State private var showingLocationPrompt = false
    @State private var showingPremiumAlert = false
    @State private var showingPremium = false
    @State private var sheetZman: ZmanimService.Zman?
    @State private var selectedDay: ZmanimDay = .today
    @State private var tomorrowZmanim: [ZmanimService.Zman] = []

    enum ZmanimDay: String, CaseIterable {
        case today, tomorrow
    }

    /// The zmanim to display based on selected day.
    private var displayedZmanim: [ZmanimService.Zman] {
        selectedDay == .today ? zmanimService.todayZmanim : tomorrowZmanim
    }

    // Premium
    private let freeAlarmLimit = 3
    @AppStorage("isPremium") private var isPremium = false

    /// All zman-linked alarms by type (unfiltered). Used for tap handling
    /// to prevent duplicate alarm creation when an alarm exists but fires on a different day.
    private var allAlarmsByZmanType: [String: Alarm] {
        Dictionary(
            allAlarms.compactMap { alarm in
                guard let raw = alarm.zmanTypeRawValue else { return nil }
                return (raw, alarm)
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Lookup: zmanType rawValue → linked Alarm, filtered to the selected day.
    /// A zman alarm's bell icon only shows on the day tab matching its next fire date,
    /// so a past-zman alarm (firing tomorrow) won't show as "set" on today's row.
    private var displayedAlarmsByZmanType: [String: Alarm] {
        let calendar = Calendar.current
        let isToday = selectedDay == .today

        return Dictionary(
            allAlarms.compactMap { alarm -> (String, Alarm)? in
                guard let raw = alarm.zmanTypeRawValue else { return nil }

                // Determine which day this alarm actually fires on
                if let fireDate = alarm.nextFireDate() {
                    let firesOnToday = calendar.isDateInToday(fireDate)
                    // Show bell only on the tab matching the fire date
                    if isToday && !firesOnToday { return nil }
                    if !isToday && firesOnToday { return nil }
                }

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
                            // Today / Tomorrow toggle
                            dayPicker
                                .padding(.top, 8)

                            let isToday = selectedDay == .today
                            let nextZmanId = isToday
                                ? displayedZmanim.first(where: { $0.time > Date() })?.id
                                : nil // No "next" concept for tomorrow

                            ForEach(ZmanSection.allCases, id: \.self) { section in
                                let sectionZmanim = displayedZmanim.filter { section.types.contains($0.type) }
                                if !sectionZmanim.isEmpty {
                                    sectionHeader(section.localizedTitle, showDate: section == .morning)

                                    LazyVStack(spacing: 6) {
                                        ForEach(sectionZmanim) { zman in
                                            let displayAlarm = displayedAlarmsByZmanType[zman.type.rawValue]
                                            let globalAlarm = allAlarmsByZmanType[zman.type.rawValue]
                                            ZmanRowView(
                                                zman: zman,
                                                isNext: zman.id == nextZmanId,
                                                isPast: isToday && zman.time <= Date(),
                                                linkedAlarm: displayAlarm,
                                                onBellTap: {
                                                    handleBellTap(for: zman, existingAlarm: globalAlarm)
                                                }
                                            )
                                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                                if displayAlarm != nil {
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
                        recalculateTomorrow()
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
            recalculateTomorrow()
        }
        .onChange(of: locationManager.location) { _, _ in
            zmanimService.calculateTodayZmanim()
            recalculateTomorrow()
        }
        .sheet(item: $sheetZman) { zman in
            let linkedAlarm = allAlarmsByZmanType[zman.type.rawValue]
            ZmanAlarmSheet(
                zman: zman,
                existingAlarm: linkedAlarm,
                onDelete: {
                    deleteAlarm(for: zman)
                }
            )
            .applyLanguageOverride(AppLanguage.current)
        }
        .alert("Upgrade to Premium", isPresented: $showingPremiumAlert) {
            Button("Maybe Later", role: .cancel) {}
            Button("Upgrade") {
                showingPremium = true
            }
        } message: {
            Text("Free users can create up to \(freeAlarmLimit) alarms. Upgrade to Premium for unlimited alarms and more sounds!")
        }
        .sheet(isPresented: $showingPremium) {
            PremiumView()
                .applyLanguageOverride(AppLanguage.current)
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
        if existingAlarm != nil {
            // Open unified sheet for existing alarm
            sheetZman = zman
        } else if canAddAlarm {
            // Open unified sheet for new alarm
            sheetZman = zman
        } else {
            showingPremiumAlert = true
        }
    }

    private func deleteAlarm(for zman: ZmanimService.Zman) {
        guard let alarm = allAlarmsByZmanType[zman.type.rawValue] else { return }
        AlarmKitService.shared.delete(alarm)
    }

    // MARK: - Day Picker

    private var dayPicker: some View {
        Picker("Day", selection: $selectedDay) {
            Text("Today").tag(ZmanimDay.today)
            Text("Tomorrow").tag(ZmanimDay.tomorrow)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
    }

    private func recalculateTomorrow() {
        guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) else { return }
        tomorrowZmanim = zmanimService.calculateZmanim(for: tomorrow)
    }

    // MARK: - Subviews

    private func sectionHeader(_ title: LocalizedStringKey, showDate: Bool = false) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.textSecondary.opacity(0.6))
                .textCase(.uppercase)

            Spacer()

            if showDate {
                Text(dateString)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.textSecondary.opacity(0.5))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 12)
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
        let date: Date
        if selectedDay == .tomorrow,
           let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) {
            date = tomorrow
        } else {
            date = Date()
        }
        return formatter.string(from: date)
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

    /// Concrete ring time subtitle (e.g., "Rings 4:53 AM · Tomorrow")
    private var alarmSubtitle: String? {
        guard let alarm = linkedAlarm, alarm.isEnabled else { return nil }
        return ZmanAlarmSyncService.shared.ringTimeDescription(for: alarm)
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
                    .foregroundStyle(alarmSubtitle != nil ? .clear : .textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .overlay(alignment: .leading) {
                        // Show concrete ring time when alarm is set, replacing English name
                        // Uses overlay so row height stays constant
                        if let subtitle = alarmSubtitle {
                            Text(subtitle)
                                .font(.system(size: 11))
                                .foregroundStyle(.accentPurple.opacity(0.8))
                                .lineLimit(1)
                        }
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

            // Bell button — hidden for past zmanim with no alarm on this day
            if !isPast || linkedAlarm != nil {
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
        .opacity(isPast ? 0.45 : 1)
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

// MARK: - Preview

#Preview {
    ZmanimView()
        .modelContainer(for: Alarm.self, inMemory: true)
        .environment(AlarmKitService.shared)
}

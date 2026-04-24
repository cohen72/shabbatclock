import SwiftUI
import SwiftData

/// Main clock view - the home screen of the app.
struct MainClockView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Alarm> { $0.isEnabled }, sort: \Alarm.hour) private var enabledAlarms: [Alarm]
    @Environment(AlarmKitService.self) private var alarmService
    @StateObject private var zmanimService = ZmanimService.shared
    @StateObject private var locationManager = LocationManager.shared

    @State private var currentTime = Date()
    @State private var showingLocationPrompt = false
    @State private var showingCitySearch = false

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient.nightSky
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        // MARK: Hero — Time + Mini Clock
                        heroTimeSection
                            .padding(.top, 4)

                        // MARK: Alarm permission banner (AlarmKit denied)
                        if !alarmService.isAuthorized && alarmService.hasBeenAskedForAuthorization {
                            AlarmPermissionBanner()
                        }

                        // MARK: Parasha Card
                        if !zmanimService.parashaHebrew.isEmpty {
                            parashaCard
                        }

                        // MARK: Shabbat Times Card
                        shabbatTimesCard

                        // MARK: Next Alarm Card
                        nextAlarmCard

                        // MARK: Location nudge (when no location)
                        if !hasValidLocation {
                            locationNudgeCard
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    toolbarLocation
                }
            }
        }
        .onAppear {
            zmanimService.calculateTodayZmanim()
            if locationManager.isAuthorized && !locationManager.isUsingManualLocation {
                locationManager.requestLocation()
            }
        }
        .onChange(of: locationManager.locationName) {
            zmanimService.calculateTodayZmanim()
        }
        .onReceive(timer) { _ in
            currentTime = Date()
        }
        .fullScreenCover(isPresented: $showingLocationPrompt) {
            PermissionPromptView.location(
                onContinue: {
                    showingLocationPrompt = false
                    locationManager.requestPermission()
                }
            )
        }
        .sheet(isPresented: $showingCitySearch) {
            CitySearchView()
                .applyLanguageOverride(AppLanguage.current)
        }
    }

    // MARK: - Toolbar Location (CARROT-style)

    private var toolbarLocation: some View {
        Button {
            showingCitySearch = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "location.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.goldAccent)

                if locationManager.locationName == "__unknown__" {
                    Text("Unknown Location")
                } else {
                    Text(locationManager.locationName)
                }

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.textSecondary.opacity(0.5))
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Hero Time Section

    private var heroTimeSection: some View {
        GeometryReader { geo in
            let halfWidth = geo.size.width / 2
            let clockSize = min(halfWidth - 16, geo.size.height - 8)

            HStack(spacing: 0) {
                // Analog clock — fills left half
                AnalogClockView(size: clockSize)
                    .frame(width: halfWidth, height: geo.size.height)

                // Digital time + Hebrew date — centered in right half
                VStack(spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(digitalTimeString)
                            .font(.system(size: 48, weight: .thin))
                            .foregroundStyle(.textPrimary)
                            .monospacedDigit()

                        Text(periodString)
                            .font(.system(size: 18, weight: .thin))
                            .foregroundStyle(.textSecondary.opacity(0.8))
                    }
                    .environment(\.layoutDirection, .leftToRight)

                    // Hebrew date (both scripts)
                    if !zmanimService.hebrewDateString.isEmpty {
                        VStack(spacing: 2) {
                            Text(zmanimService.hebrewDateString)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.goldAccent)

                            Text(zmanimService.hebrewDateEnglish)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.textSecondary.opacity(0.6))
                        }
                    }
                }
                .frame(width: halfWidth, height: geo.size.height)
            }
        }
        .frame(height: 150)
    }

    // MARK: - Parasha Card

    private var parashaCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                // Book icon in a tinted circle
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.goldAccent.opacity(0.10))
                        .frame(width: 44, height: 44)

                    Image(systemName: "book.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.goldAccent)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("CURRENT PARASHAT")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.textSecondary)
                        .tracking(1.5)

                    Text(zmanimService.parashaEnglish)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text("פרשת \(zmanimService.parashaHebrew)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.textSecondary.opacity(0.7))
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            // Countdown row at bottom
            Divider().overlay(Color.surfaceBorder)

            shabbatCountdownRow
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .themeCard(cornerRadius: 14)
    }

    private var shabbatCountdownRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar")
                .font(.system(size: 11))
                .foregroundStyle(.textSecondary)

            if zmanimService.daysUntilShabbat == 0 {
                Text("Shabbat Shalom!")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.goldAccent)
            } else if zmanimService.daysUntilShabbat == 1 {
                Text("Shabbat begins tomorrow")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.textSecondary)
            } else {
                Text("Shabbat in \(zmanimService.daysUntilShabbat) days")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.textSecondary)
            }

            Spacer()
        }
    }

    // MARK: - Shabbat Times Card

    private var shabbatTimesCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Candle Lighting
                shabbatTimeColumn(
                    icon: "flame.fill",
                    iconColor: .goldAccent,
                    label: "Candle Lighting",
                    time: hasValidLocation ? zmanimService.candleLightingTime : nil,
                    dayLabel: candleLightingDayLabel
                )

                // Vertical divider
                Rectangle()
                    .fill(Color.surfaceBorder)
                    .frame(width: 0.5)
                    .padding(.vertical, 12)

                // Havdalah
                shabbatTimeColumn(
                    icon: "moon.stars.fill",
                    iconColor: Color(hex: "8B9DC3"),
                    label: "Havdalah",
                    time: hasValidLocation ? zmanimService.havdalahTime : nil,
                    dayLabel: havdalahDayLabel
                )
            }
            .padding(.vertical, 4)
        }
        .themeCard(cornerRadius: 14)
    }

    private func shabbatTimeColumn(icon: String, iconColor: Color, label: LocalizedStringKey, time: Date?, dayLabel: String) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(iconColor)

                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }

            if let time {
                Text(zmanimService.shortTimeString(from: time))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.textPrimary)
                    .monospacedDigit()
            } else {
                Text("--:--")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.textSecondary.opacity(0.4))
                    .monospacedDigit()
            }

            Text(dayLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.textSecondary.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var candleLightingDayLabel: String {
        AppLanguage.localized("Friday Evening")
    }

    private var havdalahDayLabel: String {
        AppLanguage.localized("Saturday Night")
    }


    // MARK: - Next Alarm Card

    @ViewBuilder
    private var nextAlarmCard: some View {
        if let nextAlarm = alarmService.nextAlarmDate {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    // Alarm icon with ring accent
                    ZStack {
                        Circle()
                            .fill(Color.goldAccent.opacity(0.12))
                            .frame(width: 40, height: 40)

                        Image(systemName: "alarm.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.goldAccent)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("NEXT ALARM")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.textSecondary)
                            .tracking(1.5)

                        Text(nextAlarmTimeString(nextAlarm))
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.textPrimary)
                            .monospacedDigit()
                    }

                    Spacer()

                    // Countdown
                    let remaining = nextAlarm.timeIntervalSince(currentTime)
                    if remaining > 0 {
                        Text(longCountdownText(from: remaining))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.textSecondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .themeCard(cornerRadius: 14)
        }
    }

    // MARK: - Location Nudge Card

    private var locationNudgeCard: some View {
        Button {
            if locationManager.authorizationStatus == .denied {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } else if locationManager.authorizationStatus == .notDetermined {
                showingLocationPrompt = true
            } else {
                showingCitySearch = true
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: locationManager.authorizationStatus == .denied
                      ? "gear" : "location.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(.goldAccent)

                Text(locationManager.authorizationStatus == .denied
                     ? "Enable location in Settings"
                     : "Set location for accurate times")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.textSecondary)

                Spacer()

                Image(systemName: "chevron.forward")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.textSecondary.opacity(0.4))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .themeCard(cornerRadius: 14)
        }
        .buttonStyle(.plain)
    }

    private var hasValidLocation: Bool {
        locationManager.location != nil
    }

    private var parashaDisplayText: String {
        let isHebrew = AppLanguage.current == .hebrew
        if isHebrew {
            return "פרשת \(zmanimService.parashaHebrew)"
        } else {
            return "Parashat \(zmanimService.parashaEnglish)"
        }
    }

    // MARK: - Computed Properties

    /// Long-form countdown text shown under hero time (e.g., "in 2d 4h", "in 3h 12m", "in 45m").
    private func longCountdownText(from remaining: TimeInterval) -> String {
        let totalMinutes = Int(remaining / 60)
        let days = totalMinutes / (60 * 24)
        let hours = (totalMinutes / 60) % 24
        let minutes = totalMinutes % 60
        let body: String
        if days > 0 {
            body = hours > 0 ? "\(days)d \(hours)h" : "\(days)d"
        } else if hours > 0 {
            body = minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        } else {
            body = "\(minutes)m"
        }
        return String(format: AppLanguage.localized("in %@"), body)
    }

    private var digitalTimeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        return formatter.string(from: currentTime)
    }

    private var periodString: String {
        Calendar.current.component(.hour, from: currentTime) < 12 ? "AM" : "PM"
    }

    private func nextAlarmTimeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - Preview

#Preview {
    MainClockView()
        .modelContainer(for: Alarm.self, inMemory: true)
        .environment(AlarmKitService.shared)
}

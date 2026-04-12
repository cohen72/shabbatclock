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
        GeometryReader { geometry in
            let clockSize = min(geometry.size.width - 48, 280)

            ZStack {
                LinearGradient.nightSky
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Title
                    Text("SHABBAT CLOCK")
                        .font(.system(size: 13, weight: .semibold, design: .default))
                        .foregroundStyle(.textSecondary)
                        .tracking(3)
                        .padding(.top, 8)

                    Spacer()

                    // Analog clock
                    AnalogClockView(size: clockSize)

                    Spacer().frame(height: 24)

                    // Digital time
                    Text(timeString)
                        .font(.system(size: 72, weight: .bold, design: .default))
                        .foregroundStyle(.textPrimary)
                        .monospacedDigit()

                    // Next alarm
                    nextAlarmLabel
                        .padding(.top, 4)

                    Spacer()

                    // Shabbat dashboard
                    shabbatDashboard
                        .padding(.bottom, 16)
                }
                .padding(.horizontal, 20)
            }
        }
        .onAppear {
            zmanimService.calculateTodayZmanim()
            // Only request location if already authorized — don't prompt on launch
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
                },
                onSkip: {
                    showingLocationPrompt = false
                }
            )
        }
        .sheet(isPresented: $showingCitySearch) {
            CitySearchView()
                .applyLanguageOverride(AppLanguage.current)
        }
    }

    // MARK: - Next Alarm Label

    private var nextAlarmLabel: some View {
        Group {
            if let nextAlarm = alarmService.nextAlarmDate {
                HStack(spacing: 0) {
                    Text("NEXT ALARM: ")
                        .foregroundStyle(.textSecondary)
                    Text(nextAlarmTimeString(nextAlarm))
                        .foregroundStyle(.goldAccent)
                }
                .font(.system(size: 12, weight: .medium, design: .default))
                .tracking(2)
            } else {
                Text("NO ALARMS SET")
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundStyle(.textSecondary.opacity(0.5))
                    .tracking(2)
            }
        }
    }

    // MARK: - Shabbat Dashboard

    /// Whether we have a real location (not the fallback default).
    private var hasValidLocation: Bool {
        locationManager.location != nil
    }

    private var shabbatDashboard: some View {
        VStack(spacing: 12) {
            // Hebrew date + Location row
            HStack {
                Text(zmanimService.hebrewDateString)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.goldAccent)

                Spacer()

                LocationRow(locationManager: locationManager)
            }

            // Parasha + Shabbat times grouped card
            VStack(spacing: 0) {
                // Parasha banner with subtle gold tinted background
                if !zmanimService.parashaHebrew.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "book.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.goldAccent)

                        Text(parashaDisplayText)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.textPrimary)

                        Spacer()

                        if zmanimService.daysUntilShabbat > 0 {
                            Text(countdownText)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.textSecondary)
                        } else {
                            Text("Shabbat Shalom!")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.goldAccent)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.goldAccent.opacity(0.06))

                    Divider()
                        .overlay(Color.surfaceBorder)
                }

                // Candle lighting + Havdalah times
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        ShabbatTimeCard(
                            icon: "flame.fill",
                            iconColor: .goldAccent,
                            title: "Candle Lighting",
                            time: hasValidLocation ? zmanimService.shortTimeString(from: zmanimService.candleLightingTime) : "--:--",
                            subtitle: zmanimService.candleLightingDateLabel
                        )

                        Divider()
                            .overlay(Color.surfaceBorder)

                        ShabbatTimeCard(
                            icon: "moon.stars.fill",
                            iconColor: Color(hex: "8B9DC3"),
                            title: "Havdalah",
                            time: hasValidLocation ? zmanimService.shortTimeString(from: zmanimService.havdalahTime) : "--:--",
                            subtitle: zmanimService.havdalahDateLabel
                        )
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    // Subtle location nudge when no location set
                    if !hasValidLocation {
                        Divider()
                            .overlay(Color.surfaceBorder)

                        Button {
                            if locationManager.authorizationStatus == .denied {
                                // Location was denied — take user to iOS Settings
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            } else if locationManager.authorizationStatus == .notDetermined {
                                showingLocationPrompt = true
                            } else {
                                showingCitySearch = true
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: locationManager.authorizationStatus == .denied
                                      ? "gear" : "location.circle")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.goldAccent)

                                Text(locationManager.authorizationStatus == .denied
                                     ? "Enable location in Settings"
                                     : "Set location for accurate times")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.textSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
            .themeCard(cornerRadius: 14)
        }
    }

    private var parashaDisplayText: String {
        let isHebrew = AppLanguage.current == .hebrew
        if isHebrew {
            return "פרשת \(zmanimService.parashaHebrew)"
        } else {
            return "Parashat \(zmanimService.parashaEnglish)"
        }
    }

    private var countdownText: String {
        let days = zmanimService.daysUntilShabbat
        if days == 1 {
            return AppLanguage.localized("Tomorrow")
        } else {
            return String(format: AppLanguage.localized("In %d days"), days)
        }
    }

    // MARK: - Computed Properties

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: currentTime)
    }

    private func nextAlarmTimeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - Shabbat Time Card

struct ShabbatTimeCard: View {
    let icon: String
    let iconColor: Color
    let title: LocalizedStringKey
    let time: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Icon + title
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(iconColor)

                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.textSecondary)
            }

            // Time
            Text(time)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(time == "--:--" ? .textSecondary.opacity(0.4) : .textPrimary)

            // Subtitle (date label)
            Group {
                switch subtitle {
                case "__friday_evening__": Text("Friday Evening")
                case "__saturday_night__": Text("Saturday Night")
                default: Text(subtitle)
                }
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.textSecondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - Preview

#Preview {
    MainClockView()
        .modelContainer(for: Alarm.self, inMemory: true)
        .environment(AlarmKitService.shared)
}

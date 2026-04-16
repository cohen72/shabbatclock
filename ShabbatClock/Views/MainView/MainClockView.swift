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
            let clockSize = min(geometry.size.width - 80, 240)

            ZStack {
                LinearGradient.nightSky
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header: title + Hebrew date + location
                    header
                        .padding(.top, 8)

                    Spacer(minLength: 16)

                    // Analog clock
                    AnalogClockView(size: clockSize)

                    Spacer().frame(height: 20)

                    // Digital time — matches alarm row style (thin, h:mm + AM/PM)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(digitalTimeString)
                            .font(.system(size: 56, weight: .thin, design: .default))
                            .foregroundStyle(.textPrimary)
                            .monospacedDigit()

                        Text(periodString)
                            .font(.system(size: 22, weight: .thin, design: .default))
                            .foregroundStyle(.textSecondary.opacity(0.8))
                    }

                    // Next alarm
                    nextAlarmLabel
                        .padding(.top, 2)

                    Spacer(minLength: 20)

                    // Hero event card + secondary row
                    shabbatDashboard
                        .padding(.bottom, 16)
                }
                .padding(.horizontal, 20)
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

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 18) {
            Text("SHABBAT CLOCK")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.textSecondary)
                .tracking(3)

            HStack(spacing: 10) {
                if !zmanimService.hebrewDateString.isEmpty {
                    Text(zmanimService.hebrewDateString)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.goldAccent)

                    Text("•")
                        .font(.system(size: 10))
                        .foregroundStyle(.textSecondary.opacity(0.5))
                }

                LocationRow(locationManager: locationManager)
            }
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
                .font(.system(size: 12, weight: .medium))
                .tracking(2)
            } else {
                Text("NO ALARMS SET")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.textSecondary.opacity(0.5))
                    .tracking(2)
            }
        }
    }

    // MARK: - Shabbat Dashboard

    private var hasValidLocation: Bool {
        locationManager.location != nil
    }

    /// Which event is "next": candle lighting until it passes, then havdalah.
    private var featuredEvent: FeaturedEvent {
        let now = currentTime
        if let candle = zmanimService.candleLightingTime, candle > now {
            return .candleLighting(candle)
        }
        if let havdalah = zmanimService.havdalahTime, havdalah > now {
            return .havdalah(havdalah)
        }
        // After havdalah: show next week's candle lighting if we have it, else parasha-only
        if let candle = zmanimService.candleLightingTime {
            return .candleLighting(candle)
        }
        return .none
    }

    @ViewBuilder
    private var shabbatDashboard: some View {
        VStack(spacing: 10) {
            heroCard

            // Secondary row: the other Shabbat time + location nudge
            secondaryRow
        }
    }

    private var heroCard: some View {
        VStack(spacing: 0) {
            // Parasha strip (subtle gold tinted)
            if !zmanimService.parashaHebrew.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "book.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.goldAccent)

                    Text(parashaDisplayText)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.textPrimary)

                    Spacer()

                    if zmanimService.daysUntilShabbat == 0 {
                        Text("Shabbat Shalom!")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.goldAccent)
                    } else {
                        Text("UPCOMING")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.textSecondary.opacity(0.7))
                            .tracking(1.5)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.goldAccent.opacity(0.06))

                Divider().overlay(Color.surfaceBorder)
            }

            // Hero content: label + big time on left, ring on right
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: featuredEvent.icon)
                            .font(.system(size: 11))
                            .foregroundStyle(featuredEvent.iconColor)

                        Text("NEXT EVENT")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.textSecondary)
                            .tracking(1.5)
                    }

                    Text(featuredEvent.title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.textPrimary)

                    Text(hasValidLocation ? featuredEvent.timeString(using: zmanimService) : "--:--")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(.goldAccent)
                        .monospacedDigit()

                    if hasValidLocation, let remaining = featuredEvent.timeUntil(from: currentTime) {
                        Text(longCountdownText(from: remaining))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.textSecondary)
                    }
                }

                Spacer()

                // Promote to ring only when imminent (<12h) — otherwise text countdown above is enough
                if hasValidLocation,
                   let remaining = featuredEvent.timeUntil(from: currentTime),
                   remaining < 12 * 3600 {
                    CountdownRing(
                        progress: featuredEvent.progress(from: currentTime),
                        remaining: remaining
                    )
                    .frame(width: 82, height: 82)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .themeCard(cornerRadius: 14)
    }

    @ViewBuilder
    private var secondaryRow: some View {
        // Show the "other" time as a subtle row, or the location nudge when missing
        if !hasValidLocation {
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
                HStack(spacing: 6) {
                    Image(systemName: locationManager.authorizationStatus == .denied
                          ? "gear" : "location.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.goldAccent)

                    Text(locationManager.authorizationStatus == .denied
                         ? "Enable location in Settings"
                         : "Set location for accurate times")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.surfaceSubtle.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        } else if let other = otherEvent {
            HStack(spacing: 8) {
                Image(systemName: other.icon)
                    .font(.system(size: 11))
                    .foregroundStyle(other.iconColor)

                Text(other.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.textSecondary)

                Spacer()

                Text(other.timeString(using: zmanimService))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.textPrimary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.surfaceSubtle.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    /// The Shabbat time that isn't the featured one.
    private var otherEvent: FeaturedEvent? {
        switch featuredEvent {
        case .candleLighting:
            if let havdalah = zmanimService.havdalahTime { return .havdalah(havdalah) }
            return nil
        case .havdalah:
            if let candle = zmanimService.candleLightingTime { return .candleLighting(candle) }
            return nil
        case .none:
            return nil
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

// MARK: - Featured Event

private enum FeaturedEvent {
    case candleLighting(Date)
    case havdalah(Date)
    case none

    var date: Date? {
        switch self {
        case .candleLighting(let d), .havdalah(let d): return d
        case .none: return nil
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .candleLighting: return "Candle Lighting"
        case .havdalah: return "Havdalah"
        case .none: return ""
        }
    }

    var icon: String {
        switch self {
        case .candleLighting: return "flame.fill"
        case .havdalah: return "moon.stars.fill"
        case .none: return "calendar"
        }
    }

    var iconColor: Color {
        switch self {
        case .candleLighting: return .goldAccent
        case .havdalah: return Color(hex: "8B9DC3")
        case .none: return .textSecondary
        }
    }

    @MainActor
    func timeString(using service: ZmanimService) -> String {
        guard let d = date else { return "--:--" }
        return service.shortTimeString(from: d)
    }

    func timeUntil(from now: Date) -> TimeInterval? {
        guard let d = date, d > now else { return nil }
        return d.timeIntervalSince(now)
    }

    /// Progress 0...1, where 1 = event just starting (24h window).
    func progress(from now: Date) -> Double {
        guard let remaining = timeUntil(from: now) else { return 0 }
        let window: TimeInterval = 24 * 3600
        return max(0, min(1, 1 - (remaining / window)))
    }
}

// MARK: - Countdown Ring

private struct CountdownRing: View {
    let progress: Double
    let remaining: TimeInterval

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.surfaceBorder.opacity(0.5), lineWidth: 4)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    Color.goldAccent,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 2) {
                Text(remainingString)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.textPrimary)
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                Text("LEFT")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.textSecondary)
                    .tracking(1)
            }
            .padding(14)
        }
    }

    /// Compact form for inside the ring. Only runs when <12h remaining, so no "d" case.
    private var remainingString: String {
        let totalMinutes = Int(remaining / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

// MARK: - Preview

#Preview {
    MainClockView()
        .modelContainer(for: Alarm.self, inMemory: true)
        .environment(AlarmKitService.shared)
}

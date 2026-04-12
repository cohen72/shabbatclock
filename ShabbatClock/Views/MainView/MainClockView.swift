import SwiftUI
import SwiftData

/// Main clock view - the home screen of the app.
struct MainClockView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Alarm> { $0.isEnabled }, sort: \Alarm.hour) private var enabledAlarms: [Alarm]
    @EnvironmentObject private var alarmScheduler: AlarmScheduler
    @StateObject private var zmanimService = ZmanimService.shared
    @StateObject private var locationManager = LocationManager.shared

    @State private var currentTime = Date()

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geometry in
            let clockSize = min(geometry.size.width - 64, 260)

            ZStack {
                LinearGradient.nightSky
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Title
                    Text("SHABBAT CLOCK")
                        .font(.system(size: 13, weight: .semibold, design: .default))
                        .foregroundStyle(.textSecondary)
                        .tracking(3)
                        .padding(.top, 12)

                    Spacer().frame(height: 20)

                    // Analog clock
                    AnalogClockView(size: clockSize)

                    Spacer().frame(height: 20)

                    // Digital time
                    Text(timeString)
                        .font(.system(size: 72, weight: .bold, design: .default))
                        .foregroundStyle(.textPrimary)
                        .monospacedDigit()

                    // Next alarm
                    nextAlarmLabel
                        .padding(.top, 4)

                    Spacer()

                    // Shabbat info cards
                    shabbatCardsView
                        .padding(.horizontal, 20)

                    // Location
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .medium))
                        Text(locationManager.locationName)
                            .font(.system(size: 14, weight: .medium, design: .default))
                    }
                    .foregroundStyle(.textSecondary)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                }
                .padding(.horizontal, 24)
            }
        }
        .onAppear {
            zmanimService.calculateTodayZmanim()
            locationManager.requestLocation()
        }
        .onReceive(timer) { _ in
            currentTime = Date()
        }
    }

    // MARK: - Next Alarm Label

    private var nextAlarmLabel: some View {
        Group {
            if let nextAlarm = alarmScheduler.nextAlarmDate {
                Text("NEXT ALARM: \(nextAlarmTimeString(nextAlarm))")
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundStyle(.textSecondary)
                    .tracking(2)
            } else {
                Text("NO ALARMS SET")
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundStyle(.textSecondary.opacity(0.5))
                    .tracking(2)
            }
        }
    }

    // MARK: - Shabbat Cards

    private var shabbatCardsView: some View {
        HStack(spacing: 12) {
            // Candle Lighting card
            ShabbatInfoCard(
                icon: "flame.fill",
                iconColor: .goldAccent,
                title: "LIGHTING",
                time: zmanimService.shortTimeString(from: zmanimService.candleLightingTime),
                subtitle: zmanimService.candleLightingDateLabel
            )

            // Havdalah card
            ShabbatInfoCard(
                icon: "moon.stars.fill",
                iconColor: Color(hex: "8B9DC3"),
                title: "HAVDALAH",
                time: zmanimService.shortTimeString(from: zmanimService.havdalahTime),
                subtitle: zmanimService.havdalahDateLabel
            )
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

// MARK: - Shabbat Info Card

struct ShabbatInfoCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let time: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(iconColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .default))
                    .foregroundStyle(.textSecondary)
                    .tracking(1)

                Text(time)
                    .font(.system(size: 22, weight: .bold, design: .default))
                    .foregroundStyle(.textPrimary)

                Text(subtitle)
                    .font(.system(size: 11, weight: .medium, design: .default))
                    .foregroundStyle(.textSecondary.opacity(0.7))
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Preview

#Preview {
    MainClockView()
        .modelContainer(for: Alarm.self, inMemory: true)
        .environmentObject(AlarmScheduler.shared)
}

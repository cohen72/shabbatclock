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

                    // Shabbat info cards
                    shabbatCardsView

                    // Location
                    LocationRow(locationManager: locationManager)
                        .padding(.top, 24)
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 20)
            }
        }
        .onAppear {
            zmanimService.calculateTodayZmanim()
            if !locationManager.isUsingManualLocation {
                locationManager.requestLocation()
            }
        }
        .onReceive(timer) { _ in
            currentTime = Date()
        }
    }

    // MARK: - Next Alarm Label

    private var nextAlarmLabel: some View {
        Group {
            if let nextAlarm = alarmScheduler.nextAlarmDate {
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

    // MARK: - Shabbat Cards

    private var shabbatCardsView: some View {
        HStack(spacing: 12) {
            ShabbatInfoCard(
                icon: "flame.fill",
                iconColor: .goldAccent,
                title: "LIGHTING",
                time: zmanimService.shortTimeString(from: zmanimService.candleLightingTime),
                subtitle: zmanimService.candleLightingDateLabel
            )

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
        VStack(alignment: .leading, spacing: 0) {
            // Icon + title row — top aligned
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(iconColor)

                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .default))
                    .foregroundStyle(.textSecondary)
                    .tracking(1)
            }

            // Time — right under the title
            Text(time)
                .font(.system(size: 28, weight: .bold, design: .default))
                .foregroundStyle(.textPrimary)
                .padding(.top, 6)

            Spacer(minLength: 8)

            // Subtitle — bottom aligned
            Group {
                switch subtitle {
                case "__friday_evening__": Text("Friday Evening")
                case "__saturday_night__": Text("Saturday Night")
                default: Text(subtitle)
                }
            }
            .font(.system(size: 11, weight: .medium, design: .default))
            .foregroundStyle(.textSecondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 100)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .themeCard(cornerRadius: 16)
    }
}

// MARK: - Preview

#Preview {
    MainClockView()
        .modelContainer(for: Alarm.self, inMemory: true)
        .environmentObject(AlarmScheduler.shared)
}

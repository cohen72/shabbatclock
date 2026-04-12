import SwiftUI

/// View displaying today's Zmanim (halachic times).
struct ZmanimView: View {
    @StateObject private var zmanimService = ZmanimService.shared
    @StateObject private var locationManager = LocationManager.shared

    @State private var showingAlarmSheet = false
    @State private var showingCitySearch = false
    @State private var selectedZman: ZmanimService.Zman?

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
                    // Zmanim list
                    ScrollView {
                        VStack(spacing: 0) {
                            locationInfoView
                                .padding(.horizontal, 24)
                                .padding(.bottom, 8)

                            let nextZmanId = zmanimService.todayZmanim.first(where: { $0.time > Date() })?.id
                            LazyVStack(spacing: 6) {
                                ForEach(zmanimService.todayZmanim) { zman in
                                    ZmanRowView(zman: zman, isNext: zman.id == nextZmanId) {
                                        selectedZman = zman
                                        showingAlarmSheet = true
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
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
                if !locationManager.isUsingManualLocation {
                    locationManager.requestLocation()
                }
                zmanimService.calculateTodayZmanim()
            }
        }
        .onChange(of: locationManager.location) { _, _ in
            zmanimService.calculateTodayZmanim()
        }
        .sheet(isPresented: $showingAlarmSheet) {
            if let zman = selectedZman {
                CreateAlarmFromZmanSheet(zman: zman)
                    .applyLanguageOverride(AppLanguage.current)
            }
        }
    }

    // MARK: - Subviews

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
                locationManager.requestPermission()
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
    let onCreateAlarm: () -> Void

    @State private var showingInfo = false

    var body: some View {
        HStack(spacing: 8) {
            // Hebrew name
            Text(zman.hebrewName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.goldAccent)
                .lineLimit(1)

            // English name
            Text(zman.englishName)
                .font(.system(size: 13))
                .foregroundStyle(.textSecondary)
                .lineLimit(1)

            // "Next" badge
            if isNext {
                Text("Next")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.goldAccent)
                    )
            }

            Spacer()

            // Time
            Text(zman.timeString)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundStyle(.textPrimary)

            // Create alarm button
            Button(action: onCreateAlarm) {
                Image(systemName: "alarm.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.accentPurple)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(Color.surfaceSubtle)
                    )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.surfaceCard)
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

// MARK: - Create Alarm from Zman Sheet

struct CreateAlarmFromZmanSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var alarmScheduler: AlarmScheduler

    let zman: ZmanimService.Zman

    @State private var minutesBefore: Int = 0

    var body: some View {
        ZStack {
            LinearGradient.nightSky
                .ignoresSafeArea()

            VStack(spacing: 24) {
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

                    Button("Save") {
                        createAlarm()
                    }
                    .foregroundStyle(.accentPurple)
                    .fontWeight(.semibold)
                }
                .padding()

                // Zman info
                VStack(spacing: 8) {
                    Text(zman.englishName)
                        .font(AppFont.header(20))
                        .foregroundStyle(.textPrimary)

                    Text(zman.timeString)
                        .font(AppFont.body())
                        .foregroundStyle(.textSecondary)
                }

                // Minutes before picker
                VStack(alignment: .leading, spacing: 12) {
                    Text("Wake up before")
                        .font(AppFont.caption(12))
                        .foregroundStyle(.textSecondary)

                    Picker("Minutes before", selection: $minutesBefore) {
                        Text("At time").tag(0)
                        Text("5 min before").tag(5)
                        Text("10 min before").tag(10)
                        Text("15 min before").tag(15)
                        Text("30 min before").tag(30)
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
                .padding(.top, 8)

                Spacer()
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

        modelContext.insert(alarm)
        alarmScheduler.scheduleNotification(for: alarm)
        alarmScheduler.updateNextAlarmDate()

        dismiss()
    }
}

// MARK: - Preview

#Preview {
    ZmanimView()
        .modelContainer(for: Alarm.self, inMemory: true)
        .environmentObject(AlarmScheduler.shared)
}

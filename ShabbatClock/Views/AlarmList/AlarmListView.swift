import SwiftUI
import SwiftData

/// List view showing all alarms.
struct AlarmListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Alarm.hour) private var alarms: [Alarm]
    @EnvironmentObject private var alarmScheduler: AlarmScheduler

    @State private var selectedAlarm: Alarm?
    @State private var newAlarm: Alarm?
    @State private var showingPremiumAlert = false

    // Free tier limit
    private let freeAlarmLimit = 2
    @AppStorage("isPremium") private var isPremium = false

    var body: some View {
        ZStack {
            LinearGradient.nightSky
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if alarms.isEmpty {
                    emptyStateView
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            // Title + add button
                            headerSection
                                .padding(.horizontal, 24)
                                .padding(.top, 16)
                                .padding(.bottom, 20)

                            // Alarm list
                            LazyVStack(spacing: 12) {
                                ForEach(alarms) { alarm in
                                    AlarmRowView(alarm: alarm) { isEnabled in
                                        handleToggle(alarm: alarm, isEnabled: isEnabled)
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedAlarm = alarm
                                    }
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            deleteAlarm(alarm)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 20)

                            // Halakhic compliance banner
                            halakhicBanner
                                .padding(.horizontal, 20)
                                .padding(.top, 24)
                                .padding(.bottom, 120)
                        }
                    }
                }
            }
        }
        .sheet(item: $selectedAlarm) { alarm in
            AlarmEditView(alarm: alarm, isNew: false)
        }
        .sheet(item: $newAlarm) { alarm in
            AlarmEditView(alarm: alarm, isNew: true)
        }
        .alert("Upgrade to Premium", isPresented: $showingPremiumAlert) {
            Button("Maybe Later", role: .cancel) {}
            Button("Upgrade") {}
        } message: {
            Text("Free users can create up to \(freeAlarmLimit) alarms. Upgrade to Premium for unlimited alarms and more sounds!")
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Alarms")
                    .font(.system(size: 34, weight: .bold, design: .default))
                    .foregroundStyle(.white)

                Text("RITUAL WAKING SCHEDULE")
                    .font(.system(size: 11, weight: .semibold, design: .default))
                    .foregroundStyle(.textSecondary.opacity(0.6))
                    .tracking(2)
            }

            Spacer()

            VStack(spacing: 8) {
                Button {
                    if canAddAlarm {
                        newAlarm = Alarm()
                    } else {
                        showingPremiumAlert = true
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(Color.accentPurple)
                        )
                }

                if !isPremium {
                    Text("\(alarms.count)/\(freeAlarmLimit)")
                        .font(.system(size: 11, weight: .semibold, design: .default))
                        .foregroundStyle(.goldAccent)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 0) {
            headerSection
                .padding(.horizontal, 24)
                .padding(.top, 16)

            Spacer()

            VStack(spacing: 24) {
                Image(systemName: "alarm.waves.left.and.right")
                    .font(.system(size: 60))
                    .foregroundStyle(.textSecondary.opacity(0.5))

                VStack(spacing: 8) {
                    Text("No Alarms Yet")
                        .font(AppFont.header(20))
                        .foregroundStyle(.textPrimary)

                    Text("Tap + New Alarm to create\nyour first Shabbat alarm")
                        .font(AppFont.body(14))
                        .foregroundStyle(.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }

            Spacer()
            Spacer()
        }
    }

    // MARK: - Halakhic Compliance Banner

    private var halakhicBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(.accentPurple)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text("Halakhic Compliance")
                    .font(.system(size: 14, weight: .semibold, design: .default))
                    .foregroundStyle(.textPrimary)

                Text("All Shabbat alarms are programmed to automatically silence after 30 seconds to ensure no forbidden manual interaction is required.")
                    .font(.system(size: 12, weight: .regular, design: .default))
                    .foregroundStyle(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.accentPurple.opacity(0.2), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Actions

    private var canAddAlarm: Bool {
        isPremium || alarms.count < freeAlarmLimit
    }

    private func deleteAlarm(_ alarm: Alarm) {
        alarmScheduler.removeNotification(for: alarm)
        modelContext.delete(alarm)
        alarmScheduler.updateNextAlarmDate()
    }

    private func handleToggle(alarm: Alarm, isEnabled: Bool) {
        if isEnabled {
            alarmScheduler.scheduleNotification(for: alarm)
        } else {
            alarmScheduler.removeNotification(for: alarm)
        }
        alarmScheduler.updateNextAlarmDate()
    }
}

// MARK: - Preview

#Preview {
    AlarmListView()
        .modelContainer(for: Alarm.self, inMemory: true)
        .environmentObject(AlarmScheduler.shared)
}

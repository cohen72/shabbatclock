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
        NavigationStack {
            ZStack {
                LinearGradient.nightSky
                    .ignoresSafeArea()

                if alarms.isEmpty {
                    emptyStateView
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
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
                            .padding(.bottom, 120)
                        }
                    }
                }
            }
            .navigationTitle("Alarms")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 8) {
                        if !isPremium {
                            Text("\(alarms.count)/\(freeAlarmLimit)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.goldAccent)
                        }

                        Button {
                            if canAddAlarm {
                                newAlarm = Alarm()
                            } else {
                                showingPremiumAlert = true
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.goldAccent)
                        }
                    }
                }
            }
        }
        .sheet(item: $selectedAlarm) { alarm in
            AlarmEditView(alarm: alarm, isNew: false)
                .applyLanguageOverride(AppLanguage.current)
        }
        .sheet(item: $newAlarm) { alarm in
            AlarmEditView(alarm: alarm, isNew: true)
                .applyLanguageOverride(AppLanguage.current)
        }
        .alert("Upgrade to Premium", isPresented: $showingPremiumAlert) {
            Button("Maybe Later", role: .cancel) {}
            Button("Upgrade") {}
        } message: {
            Text("Free users can create up to \(freeAlarmLimit) alarms. Upgrade to Premium for unlimited alarms and more sounds!")
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 0) {
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

import SwiftUI
import SwiftData

/// List view showing all alarms.
struct AlarmListView: View {
  @Environment(\.modelContext) private var modelContext
  @Query(sort: \Alarm.hour) private var alarms: [Alarm]
  @Environment(AlarmKitService.self) private var alarmService
  @StateObject private var zmanimService = ZmanimService.shared
  
  @State private var selectedAlarm: Alarm?
  @State private var newAlarm: Alarm?
  @State private var showingPremiumAlert = false
  @State private var showingPremium = false
  
  // Zman alarm sheet: triggered when tapping a zman alarm in the list
  @State private var zmanSheetAlarm: Alarm?
  
  // Shabbat banner
  @State private var shabbatBannerDismissed = false

  // Free tier limit
  private let freeAlarmLimit = 3
  @AppStorage("isPremium") private var isPremium = false
  
  var body: some View {
    NavigationStack {
      ZStack {
        LinearGradient.nightSky
          .ignoresSafeArea()
        
        if alarms.isEmpty {
          emptyStateView
        } else {
          List {
            // Permission denied banner (non-dismissible)
            if alarmService.isBothDenied {
              permissionDeniedBanner
                .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            // Friday reminder banner (dismissible)
            if isErevShabbat && !shabbatBannerDismissed && !alarms.isEmpty {
              erevShabbatCard
                .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            ForEach(alarms) { alarm in
              AlarmRowView(alarm: alarm) { isEnabled in
                handleToggle(alarm: alarm, isEnabled: isEnabled)
              }
              .contentShape(Rectangle())
              .onTapGesture {
                if alarm.zmanTypeRawValue != nil {
                  // Zman alarm → open zman sheet
                  zmanSheetAlarm = alarm
                } else {
                  // Regular alarm → open edit view
                  selectedAlarm = alarm
                }
              }
              .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
              .listRowBackground(Color.clear)
              .listRowSeparator(.hidden)
              .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                  deleteAlarm(alarm)
                } label: {
                  Label("Delete", systemImage: "trash.fill")
                }
                .tint(.red)
              }
            }
          }
          .listStyle(.plain)
          .scrollContentBackground(.hidden)
          .contentMargins(.bottom, 120, for: .scrollContent)
        }
      }
      .navigationTitle("Alarms")
      .navigationBarTitleDisplayMode(.large)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          HStack(spacing: 12) {
            // Alarm count badge (free tier only)
            if !isPremium {
              Button {
                showingPremiumAlert = true
              } label: {
                HStack(spacing: 5) {
                  Image(systemName: "lock.fill")
                    .font(.system(size: 11, weight: .semibold))
                  Text("\(alarms.count)/\(freeAlarmLimit)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.goldAccent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                  Capsule()
                    .fill(Color.goldAccent.opacity(0.15))
                )
              }
            }
            
            // Add alarm menu (+)
            if canAddAlarm {
              Menu {
                Button {
                  newAlarm = Alarm()
                } label: {
                  Label("Custom Alarm", systemImage: "clock")
                }
                
                Divider()
                
                // Shabbat presets
                Section {
                  Button {
                    createPresetAlarm(
                      label: String(localized: "Shabbat Shacharit"),
                      hour: 7, minute: 30,
                      repeatDays: [6]
                    )
                  } label: {
                    Label(String(localized: "Shabbat Shacharit"), systemImage: "sunrise")
                  }

                  Button {
                    createPresetAlarm(
                      label: String(localized: "Shabbat Mincha"),
                      hour: 12, minute: 30,
                      repeatDays: [6]
                    )
                  } label: {
                    Label(String(localized: "Shabbat Mincha"), systemImage: "sun.max")
                  }
                } header: {
                  Label("Shabbat", systemImage: "moon.stars")
                }
                
                // Zman presets
                Section {
                  Button {
                    createZmanPresetAlarm(
                      zmanType: .netz,
                      minutesBefore: 0,
                      label: String(localized: "Netz Minyan")
                    )
                  } label: {
                    Label(String(localized: "Netz Minyan"), systemImage: "sunrise.fill")
                  }
                  
                  Button {
                    createZmanPresetAlarm(
                      zmanType: .alotHashachar,
                      minutesBefore: 30,
                      label: String(localized: "Early Minyan")
                    )
                  } label: {
                    Label(String(localized: "Early Minyan"), systemImage: "moon.stars")
                  }
                } header: {
                  Label("Zmanim", systemImage: "sun.min")
                }
              } label: {
                Image(systemName: "plus")
                  .font(.system(size: 20, weight: .semibold))
                  .foregroundStyle(.goldAccent)
              }
            } else {
              Button {
                showingPremiumAlert = true
              } label: {
                Image(systemName: "lock.fill")
                  .font(.system(size: 20, weight: .semibold))
                  .foregroundStyle(.goldAccent)
              }
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
    .onAppear {
      // Ensure zmanim are loaded so zman alarm sheets can find their zman
      if zmanimService.todayZmanim.isEmpty {
        zmanimService.calculateTodayZmanim()
      }
    }
    .sheet(item: $zmanSheetAlarm) { alarm in
      // Find the matching zman for this alarm
      if let rawValue = alarm.zmanTypeRawValue,
         let zman = zmanimService.todayZmanim.first(where: { $0.type.rawValue == rawValue }) {
        ZmanAlarmSheet(
          zman: zman,
          existingAlarm: alarm,
          onDelete: {
            deleteAlarm(alarm)
          }
        )
        .applyLanguageOverride(AppLanguage.current)
      } else {
        // Zmanim not loaded yet — show a brief loading state
        VStack(spacing: 16) {
          ProgressView()
            .tint(.accentPurple)
          Text("Loading zmanim…")
            .font(.system(size: 14))
            .foregroundStyle(.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient.nightSky)
        .presentationDetents([.medium])
        .onAppear {
          zmanimService.calculateTodayZmanim()
        }
      }
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
  }
  
  // MARK: - Empty State
  
  private var emptyStateView: some View {
    VStack(spacing: 0) {
      if alarmService.isBothDenied {
        permissionDeniedBanner
          .padding(.horizontal, 20)
          .padding(.top, 16)
      }

      Spacer()

      VStack(spacing: 24) {
        Image(systemName: "alarm.waves.left.and.right")
          .font(.system(size: 60))
          .foregroundStyle(.textSecondary.opacity(0.5))
        
        VStack(spacing: 8) {
          Text("No Alarms Yet")
            .font(AppFont.header(20))
            .foregroundStyle(.textPrimary)
          
          Text("Tap + to create\nyour first Shabbat alarm")
            .font(AppFont.body(14))
            .foregroundStyle(.textSecondary)
            .multilineTextAlignment(.center)
        }
      }
      
      Spacer()
      Spacer()
    }
  }
  
  // MARK: - Permission Denied Banner

  private var permissionDeniedBanner: some View {
    Button {
      if let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url)
      }
    } label: {
      HStack(spacing: 12) {
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.system(size: 16))
          .foregroundStyle(.red)

        VStack(alignment: .leading, spacing: 2) {
          Text("Alarms Can't Ring")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.textPrimary)
          Text("Allow alarms and notifications in Settings")
            .font(.system(size: 11))
            .foregroundStyle(.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer(minLength: 0)

        Image(systemName: "arrow.up.forward")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.red.opacity(0.6))
      }
      .padding(12)
      .background(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(Color.red.opacity(0.08))
          .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
              .stroke(Color.red.opacity(0.2), lineWidth: 0.5)
          )
      )
    }
  }

  // MARK: - Erev Shabbat Banner

  private var isErevShabbat: Bool {
    #if DEBUG
    if UserDefaults.standard.bool(forKey: "debugSimulateFriday") { return true }
    #endif
    let weekday = Calendar.current.component(.weekday, from: Date())
    if weekday == 6 { return true }
    if weekday == 7, let havdalah = zmanimService.havdalahTime, Date() < havdalah { return true }
    return false
  }

  private var erevShabbatCard: some View {
    HStack(spacing: 12) {
      Image(systemName: "moon.stars.fill")
        .font(.system(size: 16))
        .foregroundStyle(.goldAccent)

      VStack(alignment: .leading, spacing: 2) {
        Text("Shabbat Shalom!")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.textPrimary)
        Text("Keep the app running in the background for alarms to auto-stop.")
          .font(.system(size: 11))
          .foregroundStyle(.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 0)

      Button {
        withAnimation {
          shabbatBannerDismissed = true
        }
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(.textSecondary.opacity(0.5))
          .frame(width: 24, height: 24)
      }
      .buttonStyle(.plain)
    }
    .padding(12)
    .background(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(Color.goldAccent.opacity(0.08))
        .overlay(
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(Color.goldAccent.opacity(0.2), lineWidth: 0.5)
        )
    )
  }

  // MARK: - Actions
  
  private var canAddAlarm: Bool {
    isPremium || alarms.count < freeAlarmLimit
  }
  
  private func deleteAlarm(_ alarm: Alarm) {
    alarmService.delete(alarm)
  }
  
  private func handleToggle(alarm: Alarm, isEnabled: Bool) {
    Task {
      if isEnabled {
        // For zman alarms, sync the time from today's zmanim before re-scheduling
        // to avoid firing at a stale hour/minute
        if alarm.zmanTypeRawValue != nil {
          ZmanAlarmSyncService.shared.syncAllZmanAlarms()
        }
        await alarmService.enable(alarm)
      } else {
        alarmService.disable(alarm)
      }
    }
  }
  
  // MARK: - Presets
  
  /// Create a Shabbat preset alarm and open it in the editor for customization.
  private func createPresetAlarm(label: String, hour: Int, minute: Int, repeatDays: [Int]) {
    let alarm = Alarm(
      hour: hour,
      minute: minute,
      isEnabled: true,
      label: label,
      repeatDays: repeatDays
    )
    newAlarm = alarm
  }
  
  /// Create a zman-linked preset alarm, or open the existing one if it already exists.
  private func createZmanPresetAlarm(zmanType: ZmanimService.ZmanType, minutesBefore: Int, label: String) {
    // Check if a zman alarm already exists for this type
    if let existing = alarms.first(where: { $0.zmanTypeRawValue == zmanType.rawValue }) {
      zmanSheetAlarm = existing
      return
    }

    guard let zman = zmanimService.todayZmanim.first(where: { $0.type == zmanType }) else {
      // Zmanim not loaded — create with default time, sync will fix it
      let alarm = Alarm(label: label)
      alarm.zmanTypeRawValue = zmanType.rawValue
      alarm.zmanMinutesBefore = minutesBefore
      newAlarm = alarm
      return
    }

    let fireTime = zman.time.addingTimeInterval(-Double(minutesBefore * 60))
    let calendar = Calendar.current
    let alarm = Alarm(
      hour: calendar.component(.hour, from: fireTime),
      minute: calendar.component(.minute, from: fireTime),
      isEnabled: true,
      label: label
    )
    alarm.zmanTypeRawValue = zmanType.rawValue
    alarm.zmanMinutesBefore = minutesBefore
    
    modelContext.insert(alarm)
    Task {
      await alarmService.enable(alarm)
    }
  }
}

// MARK: - Preview

#Preview {
  AlarmListView()
    .modelContainer(for: Alarm.self, inMemory: true)
    .environment(AlarmKitService.shared)
}

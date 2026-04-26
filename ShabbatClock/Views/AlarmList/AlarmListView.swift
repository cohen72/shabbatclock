import SwiftUI
import SwiftData

/// List view showing all alarms.
struct AlarmListView: View {
  @Environment(\.modelContext) private var modelContext
  @Query(sort: \Alarm.hour) private var alarms: [Alarm]
  @Environment(AlarmKitService.self) private var alarmService
  @StateObject private var zmanimService = ZmanimService.shared
  @EnvironmentObject private var remoteConfig: RemoteConfigService
  
  @State private var selectedAlarm: Alarm?
  @State private var newAlarm: Alarm?
  @State private var showingPremiumAlert = false
  @State private var showingPremium = false
  @State private var showingPermissionAlert = false
  
  // Zman alarm sheet: triggered when tapping a zman alarm in the list
  @State private var zmanSheetAlarm: Alarm?

  // New zman alarm draft: triggered from zman presets in the + menu
  @State private var newZmanDraft: ZmanDraft?
  
  // Gate empty/list transition until after first render to avoid animating
  // the navigation title on initial appearance.
  @State private var hasAppeared = false

  // Free tier limit (driven by Remote Config)
  private var freeAlarmLimit: Int { remoteConfig.freeAlarmLimit }
  @AppStorage("isPremium") private var isPremium = false
  
  var body: some View {
    NavigationStack {
      ZStack {
        LinearGradient.nightSky
          .ignoresSafeArea()

        List {
          // Permission denied banner (shown when AlarmKit is denied — alarms can't ring)
          if !alarmService.isAuthorized && alarmService.hasBeenAskedForAuthorization {
            permissionDeniedBanner
              .listRowInsets(EdgeInsets(top: 16, leading: 20, bottom: 10, trailing: 20))
              .listRowBackground(Color.clear)
              .listRowSeparator(.hidden)
          }

          if alarms.isEmpty {
            emptyStateView
              .frame(maxWidth: .infinity, minHeight: 420)
              .listRowInsets(EdgeInsets())
              .listRowBackground(Color.clear)
              .listRowSeparator(.hidden)
              .transition(.opacity.combined(with: .scale(scale: 0.96)))
          } else {
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
              .transition(.opacity)
            }
          }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, 120, for: .scrollContent)
        .animation(hasAppeared ? .easeInOut(duration: 0.35) : nil, value: alarms.isEmpty)
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
            
            // Add alarm menu (+). When AlarmKit is denied, show a lock button
            // instead — tapping it opens an alert with a direct Settings link.
            if !alarmService.isAuthorized && alarmService.hasBeenAskedForAuthorization {
              Button {
                showingPermissionAlert = true
              } label: {
                Image(systemName: "lock.fill")
                  .font(.system(size: 20, weight: .semibold))
                  .foregroundStyle(.goldAccent)
              }
            } else if canAddAlarm {
              Menu {
                Button {
                  let currentHour = Calendar.current.component(.hour, from: Date())
                  newAlarm = Alarm(hour: currentHour, minute: 0)
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
                if remoteConfig.isZmanimTabEnabled {
                  Section {
                    Button {
                      createZmanPresetAlarm(
                        zmanType: .netz,
                        minutesBefore: 0,
                        label: String(localized: "Netz Minyan")
                      )
                    } label: {
                      Label(String(localized: "Netz Minyan"), systemImage: zmanPresetIcon(for: .netz))
                    }

                    Button {
                      createZmanPresetAlarm(
                        zmanType: .alotHashachar,
                        minutesBefore: 30,
                        label: String(localized: "Early Minyan")
                      )
                    } label: {
                      Label(String(localized: "Early Minyan"), systemImage: zmanPresetIcon(for: .alotHashachar))
                    }
                  } header: {
                    Label("Zmanim", systemImage: "sun.min")
                  }
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
      // Enable empty/list crossfade only after the first appearance so the
      // initial @Query load doesn't animate the nav title.
      DispatchQueue.main.async {
        hasAppeared = true
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
    .sheet(item: $newZmanDraft) { draft in
      if let zman = zmanimService.todayZmanim.first(where: { $0.type == draft.zmanType }) {
        ZmanAlarmSheet(
          zman: zman,
          existingAlarm: nil,
          onDelete: nil,
          initialMinutesBefore: draft.minutesBefore,
          initialLabel: draft.label
        )
        .applyLanguageOverride(AppLanguage.current)
      } else {
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
    .onChange(of: showingPremiumAlert) { _, newValue in
      if newValue { Analytics.track(.freeLimitHit(feature: .alarm)) }
    }
    .alert("Alarms Need Permission", isPresented: $showingPermissionAlert) {
      Button("Cancel", role: .cancel) {}
      Button("Open Settings") {
        if let url = URL(string: UIApplication.openSettingsURLString) {
          UIApplication.shared.open(url)
        }
      }
    } message: {
      Text("Enable alarms in Settings to let Shabbat Clock ring on schedule.")
    }
    .sheet(isPresented: $showingPremium) {
      PremiumView()
        .trigger(.alarmLimit)
        .applyLanguageOverride(AppLanguage.current)
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
    AlarmPermissionBanner()
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

  /// Bell icon mirroring ZmanimView semantics:
  /// no alarm → "bell", enabled → "bell.fill", disabled → "bell.slash".
  private func zmanPresetIcon(for zmanType: ZmanimService.ZmanType) -> String {
    guard let alarm = alarms.first(where: { $0.zmanTypeRawValue == zmanType.rawValue }) else {
      return "bell"
    }
    return alarm.isEnabled ? "bell.fill" : "bell.slash"
  }

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

    // Open ZmanAlarmSheet as a draft — user must hit Save to persist
    newZmanDraft = ZmanDraft(zmanType: zmanType, minutesBefore: minutesBefore, label: label)
  }
}

/// Draft state for creating a new zman-linked alarm via ZmanAlarmSheet.
struct ZmanDraft: Identifiable {
  let id = UUID()
  let zmanType: ZmanimService.ZmanType
  let minutesBefore: Int
  let label: String
}

// MARK: - Preview

#Preview {
  AlarmListView()
    .modelContainer(for: Alarm.self, inMemory: true)
    .environment(AlarmKitService.shared)
}

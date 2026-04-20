import UIKit
import SwiftData
import Combine

/// Keeps zman-linked alarm times in sync with daily zmanim calculations.
///
/// Zman alarms store a *rule* (`zmanTypeRawValue` + `zmanMinutesBefore`) but also
/// cache a concrete `hour`/`minute` for AlarmKit scheduling. This service recomputes
/// the cache whenever zmanim change — on app launch, foreground, location change,
/// midnight rollover, or manual refresh.
@MainActor
final class ZmanAlarmSyncService: ObservableObject {
    static let shared = ZmanAlarmSyncService()

    private var modelContext: ModelContext?
    private var cancellables = Set<AnyCancellable>()
    private var lastSyncDate: Date?
    private var isConfigured = false

    private init() {}

    // MARK: - Setup

    func configure(with modelContext: ModelContext) {
        self.modelContext = modelContext

        // Guard against multiple configure() calls (onAppear can fire multiple times)
        guard !isConfigured else { return }
        isConfigured = true

        // Sync whenever zmanim recalculate
        ZmanimService.shared.$todayZmanim
            .dropFirst() // skip initial empty value
            .sink { [weak self] zmanim in
                guard !zmanim.isEmpty else { return }
                self?.syncAllZmanAlarms()
            }
            .store(in: &cancellables)

        // Sync on significant time change (midnight, timezone change)
        NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)
            .sink { [weak self] _ in
                ZmanimService.shared.calculateTodayZmanim()
                // syncAllZmanAlarms will be called via the todayZmanim publisher above
            }
            .store(in: &cancellables)

        // Sync when app enters foreground (if stale)
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                self?.syncIfStale()
            }
            .store(in: &cancellables)

        // Initial sync
        syncAllZmanAlarms()
    }

    // MARK: - Sync

    /// Recompute all zman-linked alarm times from today's (or tomorrow's) zmanim.
    func syncAllZmanAlarms() {
        guard let modelContext else { return }

        let descriptor = FetchDescriptor<Alarm>()
        guard let allAlarms = try? modelContext.fetch(descriptor) else { return }

        var zmanAlarms = allAlarms.filter { $0.zmanTypeRawValue != nil }
        guard !zmanAlarms.isEmpty else { return }

        // Fix legacy zman alarms that were created with snoozeEnabled = true (default).
        // Zman alarms should never have snooze — it causes AlarmKit to enter a snooze
        // countdown instead of stopping, which breaks auto-stop.
        for alarm in zmanAlarms where alarm.snoozeEnabled {
            alarm.snoozeEnabled = false
        }

        // Deduplicate: if multiple alarms share the same zmanTypeRawValue, keep the newest and delete the rest
        let grouped = Dictionary(grouping: zmanAlarms, by: { $0.zmanTypeRawValue! })
        for (zmanType, alarms) in grouped where alarms.count > 1 {
            let sorted = alarms.sorted { $0.createdAt > $1.createdAt }
            let keeper = sorted[0]
            let duplicates = sorted.dropFirst()
            for dup in duplicates {
                print("[ZmanAlarmSync] Removing duplicate zman alarm for \(zmanType): \(dup.label)")
                AlarmKitService.shared.delete(dup)
            }
            // Only keep the survivor in our working list
            zmanAlarms.removeAll { alarm in duplicates.contains(where: { $0.id == alarm.id }) }
        }

        let zmanim = ZmanimService.shared.todayZmanim
        guard !zmanim.isEmpty else { return }

        // Collect alarms that need time updates
        var alarmsToReschedule: [Alarm] = []

        for alarm in zmanAlarms {
            guard let rawValue = alarm.zmanTypeRawValue,
                  let zman = zmanim.first(where: { $0.type.rawValue == rawValue }) else {
                continue
            }

            let minutesBefore = alarm.zmanMinutesBefore ?? 0
            let fireTime = computeFireTime(zmanTime: zman.time, minutesBefore: minutesBefore)

            let calendar = Calendar.current
            let newHour = calendar.component(.hour, from: fireTime)
            let newMinute = calendar.component(.minute, from: fireTime)

            // Only update if changed (avoids unnecessary AlarmKit reschedules)
            if alarm.hour != newHour || alarm.minute != newMinute {
                alarm.hour = newHour
                alarm.minute = newMinute
                if alarm.isEnabled {
                    alarmsToReschedule.append(alarm)
                }
            }
        }

        // Save model changes first, then reschedule sequentially (not concurrently)
        // to avoid racing enable() calls that create duplicate AlarmKit alarms.
        if !alarmsToReschedule.isEmpty {
            try? modelContext.save()
            Task {
                for alarm in alarmsToReschedule {
                    await AlarmKitService.shared.enable(alarm)
                }
                print("[ZmanAlarmSync] Updated \(alarmsToReschedule.count) zman alarm(s)")
            }
        }

        lastSyncDate = Date()
    }

    /// Compute the fire time for a zman alarm.
    /// If today's zman has already passed, uses tomorrow's zman time.
    private func computeFireTime(zmanTime: Date, minutesBefore: Int) -> Date {
        let fireTime = zmanTime.addingTimeInterval(-Double(minutesBefore * 60))

        // If the fire time already passed today, it will naturally fire tomorrow
        // via AlarmKit's scheduling. We still store today's time so the display
        // matches what AlarmKit will compute for the next occurrence.
        return fireTime
    }

    /// Only re-sync if it's been more than 1 hour or the day has changed.
    private func syncIfStale() {
        guard let lastSync = lastSyncDate else {
            ZmanimService.shared.calculateTodayZmanim()
            return
        }

        let calendar = Calendar.current
        let hoursSinceSync = Date().timeIntervalSince(lastSync) / 3600
        let dayChanged = !calendar.isDate(lastSync, inSameDayAs: Date())

        if hoursSinceSync > 1 || dayChanged {
            ZmanimService.shared.calculateTodayZmanim()
        }
    }

    /// Compute the next fire date for a zman alarm (for display purposes).
    /// Returns a concrete Date representing when the alarm will actually ring.
    func nextFireDate(for alarm: Alarm) -> Date? {
        guard let rawValue = alarm.zmanTypeRawValue else { return nil }

        let zmanim = ZmanimService.shared.todayZmanim
        guard let zman = zmanim.first(where: { $0.type.rawValue == rawValue }) else { return nil }

        let minutesBefore = alarm.zmanMinutesBefore ?? 0
        let fireTime = zman.time.addingTimeInterval(-Double(minutesBefore * 60))

        if fireTime > Date() {
            return fireTime
        }

        // Today's time passed — compute tomorrow's
        // We can't precisely compute tomorrow's zman without recalculating,
        // but we can approximate by adding ~24h (zmanim shift ~1-2 min/day)
        // The display will show "Tomorrow" and the sync will correct the exact time tomorrow.
        return Calendar.current.date(byAdding: .day, value: 1, to: fireTime)
    }

    /// Human-readable description of the zman alarm's ring time.
    func ringTimeDescription(for alarm: Alarm) -> String? {
        guard let fireDate = nextFireDate(for: alarm) else { return nil }

        // Use the alarm's stored hour/minute for display (not the recomputed Date)
        // so it always matches the zman time shown in the row.
        let timeStr = alarm.formattedTime

        let calendar = Calendar.current
        if calendar.isDateInToday(fireDate) {
            return String(format: AppLanguage.localized("Rings %@ · Today"), timeStr)
        } else if calendar.isDateInTomorrow(fireDate) {
            return String(format: AppLanguage.localized("Rings %@ · Tomorrow"), timeStr)
        } else {
            let dayFormatter = DateFormatter()
            dayFormatter.locale = AppLanguage.current.effectiveLocale
            dayFormatter.setLocalizedDateFormatFromTemplate("EEE")
            let dayStr = dayFormatter.string(from: fireDate)
            return String(format: AppLanguage.localized("Rings %@ · %@"), timeStr, dayStr)
        }
    }
}

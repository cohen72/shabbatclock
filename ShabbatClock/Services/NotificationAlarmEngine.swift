import AVFoundation
import Foundation
import SwiftData
import UserNotifications

/// Alternative alarm engine that delivers alarms via local notifications
/// (`UNUserNotificationCenter`) instead of AlarmKit. Gated behind the
/// `ff_use_notification_engine` Remote Config flag.
///
/// ## Why this exists
/// AlarmKit gives true alarm behavior (loops, overrides silent/DND) but has proven
/// unreliable in production (phantom alarms, mis-scheduling). This engine trades that
/// power for the predictability of plain notifications.
///
/// ## Hard limitations (by iOS design — not bugs)
/// - **Sound ≤ 30s, no loop.** A notification sound is capped at 30 seconds and plays
///   once. To approximate "ringing for N seconds" we schedule a *burst*: multiple
///   notifications spaced `burstSpacingSeconds` apart across the chosen duration.
/// - **Time-Sensitive does NOT bypass the hardware silent switch.** If the user's
///   ringer is off, these alarms may be silent. The pre-Shabbat checklist must tell
///   users to keep the ringer on. (Critical Alerts would bypass it, but Apple won't
///   approve that entitlement for a prayer-alarm use case.)
/// - **64 pending-request cap per app.** We schedule only a rolling window of upcoming
///   occurrences and re-arm on app foreground / daily sync.
///
/// ## ID scheme
/// All request identifiers are deterministic and namespaced by the SwiftData alarm's
/// stable `id`, so cancellation and reconciliation never need a stored mapping:
///   `shabbatalarm_<alarmUUID>_<occurrenceKey>_<burstIndex>`
@MainActor
final class NotificationAlarmEngine {
    static let shared = NotificationAlarmEngine()

    /// Spacing between notifications within a single alarm's burst.
    /// 30s matches the max sound length, so audio is roughly continuous across the burst.
    private static let burstSpacingSeconds: Int = 30

    /// Hard cap on burst length regardless of the alarm's configured duration, to bound
    /// notification count. 5 min / 30s = 10 notifications per occurrence worst case.
    private static let maxBurstSeconds: Int = 5 * 60

    /// How many future occurrences of a recurring alarm to schedule at once. Kept low
    /// to stay well under the 64 pending-request cap when multiplied across alarms,
    /// weekdays, and burst slots. Re-armed on every app foreground + daily sync.
    private static let recurringOccurrencesToSchedule: Int = 2

    /// Identifier namespace prefix for all alarm notifications this engine schedules.
    static let idPrefix = "shabbatalarm_"

    private init() {}

    // MARK: - Public lifecycle (mirrors the scheduling subset of AlarmKitService)

    /// Schedule (or re-schedule) all notifications for an enabled alarm.
    /// Cancels any existing notifications for this alarm first (idempotent).
    func schedule(for alarm: Alarm) async {
        cancelNotifications(forAlarmID: alarm.id)
        guard alarm.isEnabled else { return }

        // Resolve (and if needed, trim) the sound BEFORE building requests — trimming
        // is async (AVAssetExportSession) and notification sounds must be <= 30s or iOS
        // rejects them silently.
        let sound = await resolveNotificationSound(for: alarm)

        let center = UNUserNotificationCenter.current()
        let requests = buildRequests(for: alarm, sound: sound)
        for request in requests {
            do {
                try await center.add(request)
            } catch {
                print("[NotificationAlarmEngine] Failed to add request \(request.identifier): \(error)")
            }
        }
        print("[NotificationAlarmEngine] Scheduled \(requests.count) notification(s) for '\(alarm.label)' (id: \(alarm.id))")
    }

    /// Remove all pending + delivered notifications for an alarm.
    func cancel(for alarm: Alarm) {
        cancelNotifications(forAlarmID: alarm.id)
    }

    /// Cancel by alarm UUID — usable even after the SwiftData row is gone.
    func cancelNotifications(forAlarmID alarmID: UUID) {
        let prefix = Self.idPrefix + alarmID.uuidString
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
            if !ids.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: ids)
            }
        }
        center.getDeliveredNotifications { notes in
            let ids = notes.map(\.request.identifier).filter { $0.hasPrefix(prefix) }
            if !ids.isEmpty {
                center.removeDeliveredNotifications(withIdentifiers: ids)
            }
        }
    }

    /// Re-arm all enabled alarms. Called on app foreground and from daily sync so the
    /// rolling window of recurring occurrences stays populated. Also prunes orphans —
    /// any scheduled notification whose alarm UUID no longer maps to an enabled alarm.
    func syncAll(modelContext: ModelContext) async {
        let enabledAlarms: [Alarm]
        do {
            enabledAlarms = try modelContext.fetch(
                FetchDescriptor<Alarm>(predicate: #Predicate { $0.isEnabled })
            )
        } catch {
            print("[NotificationAlarmEngine] syncAll fetch failed: \(error)")
            return
        }

        let validAlarmIDs = Set(enabledAlarms.map { Self.idPrefix + $0.id.uuidString })

        // Prune orphans: any pending request not belonging to a currently-enabled alarm.
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let orphanIDs = pending.map(\.identifier).filter { id in
            id.hasPrefix(Self.idPrefix) && !validAlarmIDs.contains(where: { id.hasPrefix($0) })
        }
        if !orphanIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: orphanIDs)
            print("[NotificationAlarmEngine] Pruned \(orphanIDs.count) orphan notification(s)")
        }

        // Re-schedule every enabled alarm (rolling window refresh).
        for alarm in enabledAlarms {
            await schedule(for: alarm)
        }
    }

    /// Cancel every notification this engine owns (nuclear cleanup; mirrors
    /// `AlarmKitService.cancelAllSystemAlarms`). Returns count removed.
    @discardableResult
    func cancelAll() async -> Int {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(Self.idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeAllDeliveredNotifications()
        print("[NotificationAlarmEngine] Cancelled \(ids.count) pending alarm notification(s)")
        return ids.count
    }

    // MARK: - Request building

    private func buildRequests(for alarm: Alarm, sound: UNNotificationSound) -> [UNNotificationRequest] {
        let burstCount = burstSlotCount(for: alarm)

        if alarm.repeatDays.isEmpty {
            // One-time alarm: one occurrence at the next fire date.
            guard let fireDate = alarm.nextFireDate() else { return [] }
            return burstRequests(
                for: alarm,
                baseDate: fireDate,
                occurrenceKey: "once",
                burstCount: burstCount,
                sound: sound,
                repeats: false
            )
        }

        // Recurring: schedule the next N occurrences across matching weekdays.
        // Using non-repeating fixed-date triggers (not repeats:true) so the burst
        // offsets land precisely; the rolling window is refreshed on foreground/sync.
        var requests: [UNNotificationRequest] = []
        let occurrences = upcomingOccurrences(
            for: alarm,
            count: Self.recurringOccurrencesToSchedule
        )
        for (index, date) in occurrences.enumerated() {
            requests.append(contentsOf: burstRequests(
                for: alarm,
                baseDate: date,
                occurrenceKey: "rec\(index)",
                burstCount: burstCount,
                sound: sound,
                repeats: false
            ))
        }
        return requests
    }

    /// Build the burst of notifications for a single occurrence at `baseDate`.
    private func burstRequests(
        for alarm: Alarm,
        baseDate: Date,
        occurrenceKey: String,
        burstCount: Int,
        sound: UNNotificationSound,
        repeats: Bool
    ) -> [UNNotificationRequest] {
        var requests: [UNNotificationRequest] = []
        for burstIndex in 0..<burstCount {
            let fireDate = baseDate.addingTimeInterval(TimeInterval(burstIndex * Self.burstSpacingSeconds))
            // Skip slots already in the past (e.g. occurrence is imminent).
            guard fireDate > Date() else { continue }

            let content = UNMutableNotificationContent()
            content.title = alarm.label
            content.body = String(localized: "Time for your alarm")
            content.sound = sound
            content.interruptionLevel = .timeSensitive
            // No threadIdentifier: iOS suppresses sounds on subsequent notifications
            // grouped under the same thread (anti-spam). Each burst slot must be its own
            // top-level notification so every slot plays sound on Lock Screen.
            content.userInfo = [
                "alarmID": alarm.id.uuidString,
                "kind": "alarm"
            ]

            let comps = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: repeats)

            let id = "\(Self.idPrefix)\(alarm.id.uuidString)_\(occurrenceKey)_\(burstIndex)"
            requests.append(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
        return requests
    }

    /// Number of burst slots for an alarm's duration (>= 1).
    private func burstSlotCount(for alarm: Alarm) -> Int {
        let duration = min(max(alarm.alarmDurationSeconds, 1), Self.maxBurstSeconds)
        // Slot at t=0, then every burstSpacingSeconds until duration elapsed.
        return max(1, Int(ceil(Double(duration) / Double(Self.burstSpacingSeconds))))
    }

    /// Max notification sound length. iOS REJECTS (plays nothing, no truncation) any
    /// notification sound longer than 30s. Trim to a hair under to be safe.
    private static let maxSoundSeconds: Double = 29.0

    /// Resolve the notification sound for an alarm, trimming to <= 30s as needed.
    ///
    /// `UNNotificationSound(named:)` only resolves files in the app bundle ROOT or in a
    /// `Library/Sounds/` container dir — NOT bundle subfolders. Our bundled sounds ship
    /// inside a `Sounds/` folder reference, so they must be copied into the App Group
    /// `Library/Sounds/` (where custom recordings already live) to be playable.
    ///
    /// And any source longer than 30s must be trimmed or iOS plays silence.
    private func resolveNotificationSound(for alarm: Alarm) async -> UNNotificationSound {
        // Custom recording: already in Library/Sounds. Trim into a derived file if long.
        if let customFileName = AlarmSound.customFileName(from: alarm.soundName),
           CustomSoundStore.fileExists(fileName: customFileName),
           let srcURL = CustomSoundStore.url(for: customFileName) {
            if let name = await preparedSoundName(
                sourceURL: srcURL,
                destFileName: "notif_\(customFileName)"
            ) {
                return UNNotificationSound(named: UNNotificationSoundName(name))
            }
            return .default
        }
        // Bundled sound: copy/trim from bundle into Library/Sounds.
        if let sound = AlarmSound.sound(named: alarm.soundName),
           let srcURL = Bundle.main.url(
               forResource: "Sounds/\(sound.fileName)",
               withExtension: sound.fileExtension
           ) {
            if let name = await preparedSoundName(
                sourceURL: srcURL,
                destFileName: "notif_bundled_\(sound.fileName).\(sound.fileExtension)"
            ) {
                return UNNotificationSound(named: UNNotificationSoundName(name))
            }
        }
        return .default
    }

    /// Ensure a playable notification-sound file exists in `Library/Sounds/` for the
    /// given source. If source <= 30s, copies verbatim; if longer, trims first 29s.
    /// Cached: returns immediately if the destination already exists. Returns bare
    /// filename, or nil on failure.
    private func preparedSoundName(sourceURL: URL, destFileName: String) async -> String? {
        guard let destURL = CustomSoundStore.url(for: destFileName) else { return nil }
        if FileManager.default.fileExists(atPath: destURL.path) {
            return destFileName
        }

        let asset = AVURLAsset(url: sourceURL)
        let duration: Double
        do {
            duration = try await CMTimeGetSeconds(asset.load(.duration))
        } catch {
            print("[NotificationAlarmEngine] could not load duration: \(error)")
            // Fall back to a plain copy attempt.
            return (try? FileManager.default.copyItem(at: sourceURL, to: destURL)) != nil ? destFileName : nil
        }

        if duration <= Self.maxSoundSeconds {
            do {
                try FileManager.default.copyItem(at: sourceURL, to: destURL)
                return destFileName
            } catch {
                print("[NotificationAlarmEngine] copy failed: \(error)")
                return nil
            }
        }

        // Trim first maxSoundSeconds via export.
        return await trim(asset: asset, to: destURL, seconds: Self.maxSoundSeconds) ? destFileName : nil
    }

    /// Export the first `seconds` of `asset` to `destURL` as m4a. Returns success.
    private func trim(asset: AVURLAsset, to destURL: URL, seconds: Double) async -> Bool {
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            return false
        }
        export.outputURL = destURL
        export.outputFileType = .m4a
        export.timeRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: seconds, preferredTimescale: 600)
        )
        await export.export()
        if export.status == .completed {
            return true
        }
        print("[NotificationAlarmEngine] trim export failed: \(String(describing: export.error))")
        try? FileManager.default.removeItem(at: destURL)
        return false
    }

    // MARK: - Occurrence calculation

    /// Compute the next `count` fire dates for a recurring alarm by walking forward
    /// day by day and matching `repeatDays`.
    private func upcomingOccurrences(for alarm: Alarm, count: Int) -> [Date] {
        guard !alarm.repeatDays.isEmpty else { return [] }
        let calendar = Calendar.current
        let now = Date()
        var results: [Date] = []

        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = alarm.hour
        components.minute = alarm.minute
        components.second = 0

        // Walk up to 21 days forward to collect `count` matches (covers weekly gaps).
        for dayOffset in 0..<21 {
            guard let base = calendar.date(from: components),
                  let candidate = calendar.date(byAdding: .day, value: dayOffset, to: base) else { continue }
            guard candidate > now else { continue }
            let weekday = calendar.component(.weekday, from: candidate) - 1 // 0=Sunday
            if alarm.repeatDays.contains(weekday) {
                results.append(candidate)
                if results.count >= count { break }
            }
        }
        return results
    }
}

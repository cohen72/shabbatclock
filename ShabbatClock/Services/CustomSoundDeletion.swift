import Foundation
import SwiftData

/// Utilities for deleting a custom recording while reassigning any alarms
/// that reference it.
enum CustomSoundDeletion {
    /// Alarms (from the given SwiftData context) that use the custom sound as their sound.
    static func alarmsReferencing(_ custom: CustomSound, in context: ModelContext) -> [Alarm] {
        let targetSoundName = AlarmSound.customSoundName(fileName: custom.fileName)
        let descriptor = FetchDescriptor<Alarm>()
        guard let all = try? context.fetch(descriptor) else { return [] }
        return all.filter { $0.soundName == targetSoundName }
    }

    /// Delete a custom recording:
    ///  - reassigns any referencing alarms to `fallbackSoundName` (or the app's default)
    ///  - reschedules those alarms so AlarmKit picks up the new sound
    ///  - removes the audio file from disk
    ///  - deletes the SwiftData row
    ///
    /// Caller is responsible for confirming with the user before invoking.
    @MainActor
    static func delete(
        _ custom: CustomSound,
        in context: ModelContext,
        fallbackSoundName: String = AlarmSound.defaultSound.name,
        alarmService: AlarmKitService = .shared
    ) async {
        let affected = alarmsReferencing(custom, in: context)

        for alarm in affected {
            alarm.soundName = fallbackSoundName
            // If the alarm is currently enabled, re-enable() to cancel+reschedule with
            // the new sound. If disabled, just saving is enough.
            if alarm.isEnabled {
                await alarmService.enable(alarm)
            }
        }

        CustomSoundStore.deleteFile(fileName: custom.fileName)
        context.delete(custom)
        try? context.save()
    }
}

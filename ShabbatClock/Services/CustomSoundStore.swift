import Foundation

/// File-system manager for user-recorded alarm sounds.
///
/// Recordings live in the App Group's `Library/Sounds/` directory so that
/// AlarmKit's `AlertSound.named("filename.m4a")` can resolve them. This location
/// was validated via a spike — sandbox `~/Library/Sounds/` did not work reliably,
/// but the App Group container does.
enum CustomSoundStore {
    static let appGroupID = "group.works.delicious.shabbatclock"
    static let fileExtension = "m4a"

    /// The directory where custom recordings are stored.
    /// Created on first access if it doesn't exist.
    static var soundsDirectory: URL? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else {
            print("[CustomSoundStore] Could not access App Group container")
            return nil
        }
        let dir = container
            .appendingPathComponent("Library")
            .appendingPathComponent("Sounds")
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true
            )
        }
        return dir
    }

    /// Full URL for a stored recording's filename.
    static func url(for fileName: String) -> URL? {
        soundsDirectory?.appendingPathComponent(fileName)
    }

    /// Generate a unique filename for a new recording.
    static func makeFileName() -> String {
        let timestamp = Int(Date().timeIntervalSince1970)
        return "custom_\(timestamp).\(fileExtension)"
    }

    /// Check whether a recording's file is still present on disk.
    static func fileExists(fileName: String) -> Bool {
        guard let url = url(for: fileName) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Delete a recording's file. Safe to call even if the file is missing.
    static func deleteFile(fileName: String) {
        guard let url = url(for: fileName) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// The reference passed to `AlertSound.named()` for a given custom recording.
    /// Based on spike results: bare filename (no "Sounds/" prefix) works when
    /// the file is in the App Group's `Library/Sounds/` directory.
    static func alertSoundName(for fileName: String) -> String {
        fileName
    }
}

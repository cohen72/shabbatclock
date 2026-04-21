import Foundation
import SwiftData

/// A user-recorded alarm sound stored in the App Group's Library/Sounds directory.
/// Only the metadata lives in SwiftData — the audio file itself lives on disk
/// so AlarmKit's AlertSound.named() can resolve it.
@Model
final class CustomSound {
    var id: UUID
    /// User-given display name (e.g., "My Morning Melody").
    var name: String
    /// Filename inside the App Group's Library/Sounds directory (e.g., "custom_1713600000.m4a").
    var fileName: String
    /// Length in seconds after trimming.
    var duration: Double
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        fileName: String,
        duration: Double,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.fileName = fileName
        self.duration = duration
        self.createdAt = createdAt
    }
}

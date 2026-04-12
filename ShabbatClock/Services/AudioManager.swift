@preconcurrency
import AVFoundation

/// Manages audio playback for sound previews in the alarm edit screen.
/// Alarm playback is now handled by AlarmKit at the system level.
@MainActor
final class AudioManager: ObservableObject {
    static let shared = AudioManager()

    private var previewPlayer: AVAudioPlayer?

    private init() {}

    // MARK: - Preview Playback

    /// Play a sound for preview (short duration, no loop).
    func playPreview(sound: AlarmSound) {
        stopPreview()

        guard let url = sound.url else {
            print("[AudioManager] Preview sound file not found: \(sound.name)")
            return
        }

        do {
            previewPlayer = try AVAudioPlayer(contentsOf: url)
            previewPlayer?.numberOfLoops = 0
            previewPlayer?.volume = 1.0
            previewPlayer?.prepareToPlay()
            previewPlayer?.play()

            // Auto-stop after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                self?.stopPreview()
            }
        } catch {
            print("[AudioManager] Failed to play preview: \(error)")
        }
    }

    /// Stop the currently playing preview.
    func stopPreview() {
        previewPlayer?.stop()
        previewPlayer = nil
    }

    /// Check if a sound file exists and is playable.
    func isSoundAvailable(_ sound: AlarmSound) -> Bool {
        guard let url = sound.url else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
}

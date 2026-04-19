@preconcurrency
import AVFoundation

/// Manages audio playback for sound previews in the alarm edit screen.
/// Alarm playback is now handled by AlarmKit at the system level.
@MainActor
final class AudioManager: ObservableObject {
    static let shared = AudioManager()

    private var previewPlayer: AVAudioPlayer?
    private var autoStopTask: Task<Void, Never>?

    /// Called when a preview auto-stops (timer expiry or playback finished).
    /// Views should observe this to reset their UI state.
    var onPreviewStopped: (() -> Void)?

    private init() {}

    // MARK: - Preview Playback

    /// Play a sound for preview. Plays for up to 15 seconds or until the track ends, whichever is shorter.
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

            // Auto-stop after 15 seconds or when track ends, whichever is shorter
            let duration = min(previewPlayer?.duration ?? 15.0, 15.0)
            autoStopTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(duration))
                guard !Task.isCancelled else { return }
                self?.stopPreview()
                self?.onPreviewStopped?()
            }
        } catch {
            print("[AudioManager] Failed to play preview: \(error)")
        }
    }

    /// Stop the currently playing preview.
    func stopPreview() {
        autoStopTask?.cancel()
        autoStopTask = nil
        previewPlayer?.stop()
        previewPlayer = nil
    }

    /// Check if a sound file exists and is playable.
    func isSoundAvailable(_ sound: AlarmSound) -> Bool {
        guard let url = sound.url else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
}

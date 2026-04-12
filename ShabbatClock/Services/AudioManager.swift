@preconcurrency
import AVFoundation
import Combine

/// Manages audio playback for alarm sounds and sound previews.
@MainActor
final class AudioManager: ObservableObject {
    static let shared = AudioManager()

    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentlyPlayingSound: AlarmSound?

    private var audioPlayer: AVAudioPlayer?
    private var previewPlayer: AVAudioPlayer?
    private var fadeTimer: Timer?

    private init() {}

    // MARK: - Alarm Playback

    /// Play an alarm sound, looping until stopped.
    /// - Parameters:
    ///   - sound: The alarm sound to play
    ///   - fadeIn: Whether to fade in the volume (default: true)
    ///   - fadeInDuration: Duration of fade in (default: 2 seconds)
    func playAlarm(sound: AlarmSound, fadeIn: Bool = true, fadeInDuration: TimeInterval = 2.0) {
        stopAlarm()

        guard let url = sound.url else {
            print("[AudioManager] Sound file not found: \(sound.name)")
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.numberOfLoops = -1 // Loop indefinitely
            audioPlayer?.prepareToPlay()

            if fadeIn {
                audioPlayer?.volume = 0.0
                audioPlayer?.play()
                fadeInVolume(duration: fadeInDuration)
            } else {
                audioPlayer?.volume = 1.0
                audioPlayer?.play()
            }

            isPlaying = true
            currentlyPlayingSound = sound
            print("[AudioManager] Playing alarm: \(sound.name)")
        } catch {
            print("[AudioManager] Failed to play alarm: \(error)")
        }
    }

    /// Stop the currently playing alarm.
    /// - Parameter fadeOut: Whether to fade out the volume before stopping
    func stopAlarm(fadeOut: Bool = false) {
        fadeTimer?.invalidate()
        fadeTimer = nil

        if fadeOut && audioPlayer?.isPlaying == true {
            fadeOutVolume(duration: 1.0) { [weak self] in
                self?.audioPlayer?.stop()
                self?.audioPlayer = nil
                self?.isPlaying = false
                self?.currentlyPlayingSound = nil
            }
        } else {
            audioPlayer?.stop()
            audioPlayer = nil
            isPlaying = false
            currentlyPlayingSound = nil
        }

        print("[AudioManager] Alarm stopped")
    }

    // MARK: - Preview Playback

    /// Play a sound for preview (short duration, no loop).
    /// - Parameter sound: The sound to preview
    func playPreview(sound: AlarmSound) {
        stopPreview()

        guard let url = sound.url else {
            print("[AudioManager] Preview sound file not found: \(sound.name)")
            return
        }

        do {
            previewPlayer = try AVAudioPlayer(contentsOf: url)
            previewPlayer?.numberOfLoops = 0 // Play once
            previewPlayer?.volume = 1.0
            previewPlayer?.prepareToPlay()
            previewPlayer?.play()

            // Auto-stop after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                self?.stopPreview()
            }

            print("[AudioManager] Playing preview: \(sound.name)")
        } catch {
            print("[AudioManager] Failed to play preview: \(error)")
        }
    }

    /// Stop the currently playing preview.
    func stopPreview() {
        previewPlayer?.stop()
        previewPlayer = nil
    }

    // MARK: - Volume Control

    private func fadeInVolume(duration: TimeInterval, targetVolume: Float = 1.0) {
        fadeTimer?.invalidate()

        let steps = 20
        let interval = duration / Double(steps)
        let volumeStep = targetVolume / Float(steps)
        var currentStep = 0

        fadeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
            Task { @MainActor in
                currentStep += 1
                let newVolume = volumeStep * Float(currentStep)
                self?.audioPlayer?.volume = min(newVolume, targetVolume)

                if currentStep >= steps {
                    timer.invalidate()
                    self?.fadeTimer = nil
                }
            }
        }
    }

    private func fadeOutVolume(duration: TimeInterval, completion: @escaping @MainActor () -> Void) {
        fadeTimer?.invalidate()

        guard let player = audioPlayer else {
            completion()
            return
        }

        let steps = 20
        let interval = duration / Double(steps)
        let initialVolume = player.volume
        let volumeStep = initialVolume / Float(steps)
        var currentStep = 0

        fadeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
            Task { @MainActor in
                currentStep += 1
                let newVolume = initialVolume - volumeStep * Float(currentStep)
                self?.audioPlayer?.volume = max(newVolume, 0.0)

                if currentStep >= steps {
                    timer.invalidate()
                    self?.fadeTimer = nil
                    completion()
                }
            }
        }
    }

    // MARK: - Utility

    /// Check if a sound file exists and is playable.
    func isSoundAvailable(_ sound: AlarmSound) -> Bool {
        guard let url = sound.url else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
}

@preconcurrency
import AVFoundation

/// Manages audio playback for sound previews in the alarm edit screen.
/// Alarm playback is now handled by AlarmKit at the system level.
@MainActor
final class AudioManager: ObservableObject {
    static let shared = AudioManager()

    private var previewPlayer: AVAudioPlayer?
    private var autoStopTask: Task<Void, Never>?

    /// Ambient background player (onboarding music, in-app ambience).
    /// Uses `.ambient` audio session so it mixes with other apps and is silenced
    /// by the ring/silent switch — the right behavior for atmospheric audio.
    private var backgroundPlayer: AVAudioPlayer?
    private var backgroundFadeTask: Task<Void, Never>?

    /// Target volume when background music is playing at full.
    /// Kept below 1.0 so it sits under UI sounds and doesn't startle.
    private let backgroundTargetVolume: Float = 0.35

    /// Called when a preview auto-stops (timer expiry or playback finished).
    /// Views should observe this to reset their UI state.
    var onPreviewStopped: (() -> Void)?

    private init() {}

    // MARK: - Preview Playback

    /// Play a bundled sound for preview. Plays for up to 15 seconds or until the track ends.
    func playPreview(sound: AlarmSound) {
        guard let url = sound.url else {
            print("[AudioManager] Preview sound file not found: \(sound.name)")
            return
        }
        playPreview(url: url)
    }

    /// Play a user-recorded custom sound for preview.
    func playPreview(customFileName: String) {
        guard let url = CustomSoundStore.url(for: customFileName),
              FileManager.default.fileExists(atPath: url.path) else {
            print("[AudioManager] Custom recording file missing: \(customFileName)")
            return
        }
        playPreview(url: url)
    }

    /// Shared preview implementation for a resolved file URL.
    private func playPreview(url: URL) {
        stopPreview()
        do {
            previewPlayer = try AVAudioPlayer(contentsOf: url)
            previewPlayer?.numberOfLoops = 0
            previewPlayer?.volume = 1.0
            previewPlayer?.prepareToPlay()
            previewPlayer?.play()

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

    // MARK: - Background (Ambient) Music

    /// Starts looping ambient background music for the given sound, fading in.
    /// Uses the `.ambient` audio session category: mixes with other audio,
    /// respects the silent switch, and does not continue in the background.
    ///
    /// If a background track is already playing, this is a no-op — call `stopBackgroundMusic()` first
    /// if you need to switch tracks.
    func startBackgroundMusic(sound: AlarmSound, fadeInDuration: TimeInterval = 2.0) {
        guard backgroundPlayer == nil else { return }
        guard let url = sound.url else {
            print("[AudioManager] Background sound file not found: \(sound.name)")
            return
        }

        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)

            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1  // loop indefinitely
            player.volume = 0
            player.prepareToPlay()
            player.play()
            backgroundPlayer = player

            fadeBackgroundVolume(to: backgroundTargetVolume, duration: fadeInDuration)
        } catch {
            print("[AudioManager] Failed to start background music: \(error)")
        }
    }

    /// Stops the background music with a fade-out.
    func stopBackgroundMusic(fadeOutDuration: TimeInterval = 1.0) {
        guard backgroundPlayer != nil else { return }
        fadeBackgroundVolume(to: 0, duration: fadeOutDuration) { [weak self] in
            self?.backgroundPlayer?.stop()
            self?.backgroundPlayer = nil
        }
    }

    /// True if background music is currently playing (or fading out).
    var isBackgroundMusicPlaying: Bool {
        backgroundPlayer?.isPlaying == true
    }

    /// Linear volume fade on the background player.
    private func fadeBackgroundVolume(to target: Float, duration: TimeInterval, completion: (() -> Void)? = nil) {
        backgroundFadeTask?.cancel()

        guard let player = backgroundPlayer else {
            completion?()
            return
        }

        let startVolume = player.volume
        let steps = max(1, Int(duration * 30))  // ~30fps
        let stepDuration = duration / Double(steps)

        backgroundFadeTask = Task { [weak self] in
            for step in 1...steps {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .seconds(stepDuration))
                guard !Task.isCancelled, let self else { return }
                let progress = Float(step) / Float(steps)
                self.backgroundPlayer?.volume = startVolume + (target - startVolume) * progress
            }
            completion?()
        }
    }
}

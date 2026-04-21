import Foundation
import AVFoundation
import Observation

/// Manages the audio recording lifecycle for custom alarm sounds.
///
/// Records to a temporary file as AAC (.m4a) — matches ShabbatClock's bundled
/// alarm sounds and is a format AlarmKit resolves reliably. Supports live audio
/// metering for waveform visualization, trim range adjustment, and preview playback.
///
/// On save, exports (trimmed) or moves the file into the App Group's
/// `Library/Sounds/` directory where AlarmKit can resolve it via `AlertSound.named()`.
@MainActor
@Observable
final class AudioRecordingManager: NSObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    static let shared = AudioRecordingManager()

    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    private var previewPlayer: AVAudioPlayer?
    private var previewTimer: Timer?

    /// Whether a recording is currently being captured.
    var isRecording = false
    /// Elapsed time of the current / last recording in seconds.
    var recordingDuration: TimeInterval = 0
    /// URL of the temporary recording once stopped (nil during recording, nil after save/cancel).
    var lastRecordedUrl: URL?
    /// Normalized instantaneous audio level (0.0–1.0) for live visualization.
    var audioLevel: CGFloat = 0
    /// Sampled audio level history for waveform display (one entry per 0.1s).
    var levels: [CGFloat] = []
    /// Trim start time (seconds into the recording).
    var trimStartTime: TimeInterval = 0
    /// Trim end time (seconds into the recording).
    var trimEndTime: TimeInterval = 0
    /// Whether the trimmed preview is currently playing.
    var isPlayingPreview = false

    /// Maximum recording length. AlarmKit plays sounds on a loop during alert,
    /// so 30s is enough for a melody and keeps file size small.
    static let maxDuration: TimeInterval = 30.0

    private override init() {
        super.init()
    }

    // MARK: - State

    /// Reset all recording state. Call when entering the recording UI.
    func reset() {
        stopPreview()
        isRecording = false
        recordingDuration = 0
        lastRecordedUrl = nil
        audioLevel = 0
        levels = []
        trimStartTime = 0
        trimEndTime = 0
    }

    // MARK: - Recording

    /// Start recording to a fresh temporary file. Returns true if recording started.
    /// Caller must verify microphone permission before calling.
    @discardableResult
    func startRecording() async -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, options: .defaultToSpeaker)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100.0,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("shabbatclock_recording.m4a")
            try? FileManager.default.removeItem(at: tempURL)

            let recorder = try AVAudioRecorder(url: tempURL, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            recorder.prepareToRecord()

            guard recorder.record() else {
                return false
            }

            audioRecorder = recorder
            isRecording = true
            recordingDuration = 0
            levels = []
            lastRecordedUrl = nil
            startTimer()
            return true
        } catch {
            print("[AudioRecordingManager] Failed to start recording: \(error)")
            return false
        }
    }

    /// Stop the in-progress recording. Sets `lastRecordedUrl` and initial trim range.
    func stopRecording() {
        guard let recorder = audioRecorder else { return }
        recorder.stop()
        stopTimer()
        isRecording = false
        lastRecordedUrl = recorder.url
        audioLevel = 0
        trimStartTime = 0
        trimEndTime = recordingDuration

        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    /// Discard the current recording.
    func cancelRecording() {
        stopRecording()
        if let url = lastRecordedUrl {
            try? FileManager.default.removeItem(at: url)
        }
        lastRecordedUrl = nil
        recordingDuration = 0
        levels = []
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let recorder = self.audioRecorder else { return }
                recorder.updateMeters()
                let decibels = recorder.averagePower(forChannel: 0)
                // Map -60..0 dB to 0..1
                let level = max(0, CGFloat(decibels + 60) / 60)
                self.audioLevel = level
                self.levels.append(level)
                self.recordingDuration += 0.1

                if self.recordingDuration >= Self.maxDuration {
                    self.stopRecording()
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Save

    /// Save the current recording to the App Group's sounds directory.
    /// Returns the filename on success (e.g., "custom_1713600000.m4a"), nil on failure.
    /// Applies the active trim range if set.
    func saveRecording() async -> String? {
        guard let sourceURL = lastRecordedUrl else { return nil }
        guard let soundsDir = CustomSoundStore.soundsDirectory else { return nil }

        let fileName = CustomSoundStore.makeFileName()
        let destURL = soundsDir.appendingPathComponent(fileName)

        // If the user trimmed the recording, export the trimmed range.
        let needsTrim = trimStartTime > 0.05
            || (recordingDuration - trimEndTime) > 0.05

        if needsTrim {
            let asset = AVURLAsset(url: sourceURL)
            guard let exporter = AVAssetExportSession(
                asset: asset,
                presetName: AVAssetExportPresetAppleM4A
            ) else {
                return nil
            }
            let start = CMTime(seconds: trimStartTime, preferredTimescale: 600)
            let durationCM = CMTime(
                seconds: trimEndTime - trimStartTime,
                preferredTimescale: 600
            )
            exporter.timeRange = CMTimeRange(start: start, duration: durationCM)
            do {
                try await exporter.export(to: destURL, as: .m4a)
                try? FileManager.default.removeItem(at: sourceURL)
                lastRecordedUrl = nil
                return fileName
            } catch {
                print("[AudioRecordingManager] Export failed: \(error)")
                return nil
            }
        } else {
            do {
                if FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.removeItem(at: destURL)
                }
                try FileManager.default.moveItem(at: sourceURL, to: destURL)
                lastRecordedUrl = nil
                return fileName
            } catch {
                print("[AudioRecordingManager] Move failed: \(error)")
                return nil
            }
        }
    }

    // MARK: - Preview

    /// Play the current temporary recording, respecting trim range.
    func playPreview() {
        guard let url = lastRecordedUrl else { return }
        stopPreview()
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.currentTime = trimStartTime
            guard player.play() else { return }
            previewPlayer = player
            isPlayingPreview = true
            startPreviewTimer()
        } catch {
            print("[AudioRecordingManager] Preview failed: \(error)")
        }
    }

    func stopPreview() {
        previewPlayer?.stop()
        previewPlayer = nil
        previewTimer?.invalidate()
        previewTimer = nil
        isPlayingPreview = false
    }

    private func startPreviewTimer() {
        previewTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let player = self.previewPlayer else { return }
                if player.currentTime >= self.trimEndTime {
                    self.stopPreview()
                }
            }
        }
    }

    // MARK: - AVAudioPlayerDelegate

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            AudioRecordingManager.shared.stopPreview()
        }
    }
}

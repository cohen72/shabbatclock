import AVFoundation
import BackgroundTasks
import Combine
import UIKit

/// Manages background audio playback to keep the app alive.
/// Uses a quiet (not silent) tone to avoid iOS suspending the app.
/// Also integrates with Background App Refresh for additional resilience.
@MainActor
final class BackgroundKeepAlive: ObservableObject {
    static let shared = BackgroundKeepAlive()

    @Published private(set) var isActive: Bool = false
    @Published private(set) var lastRefreshDate: Date?
    
    // Background task identifier
    static let backgroundTaskIdentifier = "com.shabbatclock.keepalive"
    
    private var queuePlayer: AVQueuePlayer?
    private var playerLooper: AVPlayerLooper?
    private var healthCheckTimer: Timer?
    private var audioSessionRefreshTimer: Timer?
    
    // Track playback health
    private var lastPlaybackCheck: Date?
    private var consecutiveFailures: Int = 0
    private let maxConsecutiveFailures = 3

    private init() {
        setupNotifications()
        registerBackgroundTasks()
    }

    // MARK: - Audio Session Setup

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            
            // Use playback category for background audio
            // .mixWithOthers: Don't interrupt user's music
            // .duckOthers: Slightly lower other audio (optional, can remove)
            try session.setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers]
            )
            
            // Activate the session
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            
            print("[BackgroundKeepAlive] Audio session configured successfully")
        } catch {
            print("[BackgroundKeepAlive] Failed to configure audio session: \(error)")
        }
    }
    
    /// Re-activate audio session - call periodically to maintain background state
    private func refreshAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            
            // Briefly deactivate and reactivate to refresh the session
            if session.isOtherAudioPlaying == false {
                try session.setActive(false, options: .notifyOthersOnDeactivation)
                try session.setActive(true, options: .notifyOthersOnDeactivation)
            }
            
            lastRefreshDate = Date()
            print("[BackgroundKeepAlive] Audio session refreshed at \(Date())")
        } catch {
            print("[BackgroundKeepAlive] Failed to refresh audio session: \(error)")
        }
    }

    // MARK: - Background Tasks Registration
    
    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.backgroundTaskIdentifier,
            using: nil
        ) { [weak self] task in
            Task { @MainActor in
                self?.handleBackgroundTask(task as! BGAppRefreshTask)
            }
        }
    }
    
    /// Schedule the next background app refresh
    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
        // Request to run within 15 minutes (iOS may delay this)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("[BackgroundKeepAlive] Background refresh scheduled")
        } catch {
            print("[BackgroundKeepAlive] Failed to schedule background refresh: \(error)")
        }
    }
    
    private func handleBackgroundTask(_ task: BGAppRefreshTask) {
        // Schedule the next refresh
        scheduleBackgroundRefresh()
        
        // Refresh audio session and ensure playback is active
        if isActive {
            refreshAudioSession()
            ensurePlaybackActive()
        }
        
        // Mark task complete
        task.setTaskCompleted(success: true)
        print("[BackgroundKeepAlive] Background task completed")
    }

    // MARK: - Notifications

    private func setupNotifications() {
        let nc = NotificationCenter.default
        
        // Audio interruption handling
        nc.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleInterruption(notification)
            }
        }
        
        // Route change handling (headphones plugged/unplugged, etc.)
        nc.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleRouteChange(notification)
            }
        }

        // App lifecycle
        nc.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                if self?.isActive == true {
                    self?.refreshAudioSession()
                    self?.ensurePlaybackActive()
                }
            }
        }
        
        nc.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                if self?.isActive == true {
                    // Ensure we're ready for background
                    self?.ensurePlaybackActive()
                    self?.scheduleBackgroundRefresh()
                }
            }
        }
        
        nc.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                if self?.isActive == true {
                    print("[BackgroundKeepAlive] App entered background - audio should continue")
                }
            }
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            print("[BackgroundKeepAlive] Audio interrupted")
            
        case .ended:
            print("[BackgroundKeepAlive] Audio interruption ended")
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    // Delay slightly before resuming to let system settle
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        Task { @MainActor in
                            self?.refreshAudioSession()
                            self?.ensurePlaybackActive()
                        }
                    }
                }
            }
            
        @unknown default:
            break
        }
    }
    
    private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        switch reason {
        case .oldDeviceUnavailable:
            // Headphones unplugged - resume on speaker
            print("[BackgroundKeepAlive] Audio route changed - resuming playback")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                Task { @MainActor in
                    self?.ensurePlaybackActive()
                }
            }
        default:
            break
        }
    }

    // MARK: - Start/Stop

    /// Start quiet audio playback to keep the app alive in the background.
    func start() {
        guard !isActive else {
            print("[BackgroundKeepAlive] Already active")
            return
        }

        setupAudioSession()
        
        // Try quiet_tone.m4a first (preferred), then fall back to silence.mp3
        if let quietToneURL = Bundle.main.url(forResource: "quiet_tone", withExtension: "m4a", subdirectory: "Sounds") {
            setupPlayer(url: quietToneURL)
            print("[BackgroundKeepAlive] Using quiet_tone.m4a")
        } else if let silenceURL = Bundle.main.url(forResource: "silence", withExtension: "mp3", subdirectory: "Sounds") {
            setupPlayer(url: silenceURL)
            print("[BackgroundKeepAlive] Using silence.mp3 (fallback)")
        } else {
            print("[BackgroundKeepAlive] ERROR: No audio file found! Background mode may not work.")
            // Still mark as active so we can try other approaches
        }

        isActive = true
        consecutiveFailures = 0
        
        // Start health check timer
        startHealthCheck()
        
        // Start periodic audio session refresh (every 5 minutes)
        startAudioSessionRefresh()
        
        // Schedule background refresh
        scheduleBackgroundRefresh()
        
        print("[BackgroundKeepAlive] Started - app will remain active in background")
    }

    /// Stop quiet audio playback.
    func stop() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
        
        audioSessionRefreshTimer?.invalidate()
        audioSessionRefreshTimer = nil
        
        queuePlayer?.pause()
        queuePlayer = nil
        playerLooper = nil
        
        isActive = false
        consecutiveFailures = 0
        
        print("[BackgroundKeepAlive] Stopped")
    }

    // MARK: - Player Setup

    private func setupPlayer(url: URL) {
        let asset = AVAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)

        queuePlayer = AVQueuePlayer(playerItem: playerItem)
        
        // Set volume very low but not zero (iOS may optimize away zero-volume audio)
        queuePlayer?.volume = 0.01
        
        // Disable video tracks if any (saves resources)
        queuePlayer?.currentItem?.preferredForwardBufferDuration = 1.0

        if let queuePlayer = queuePlayer {
            // Loop indefinitely
            playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem)
            queuePlayer.play()
        }
    }

    // MARK: - Health Monitoring
    
    private func startHealthCheck() {
        healthCheckTimer?.invalidate()
        
        // Check every 30 seconds that playback is still active
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.performHealthCheck()
            }
        }
        
        if let timer = healthCheckTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    
    private func performHealthCheck() {
        guard isActive else { return }
        
        let isPlaying = queuePlayer?.timeControlStatus == .playing
        
        if !isPlaying {
            consecutiveFailures += 1
            print("[BackgroundKeepAlive] Health check FAILED (\(consecutiveFailures)/\(maxConsecutiveFailures)) - attempting recovery")
            
            if consecutiveFailures >= maxConsecutiveFailures {
                // Full restart
                print("[BackgroundKeepAlive] Too many failures - performing full restart")
                restartPlayback()
            } else {
                // Try simple resume
                ensurePlaybackActive()
            }
        } else {
            consecutiveFailures = 0
            lastPlaybackCheck = Date()
            print("[BackgroundKeepAlive] Health check OK - playback active")
        }
    }
    
    private func startAudioSessionRefresh() {
        audioSessionRefreshTimer?.invalidate()
        
        // Refresh audio session every 5 minutes
        audioSessionRefreshTimer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAudioSession()
            }
        }
        
        if let timer = audioSessionRefreshTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    
    private func restartPlayback() {
        // Stop everything
        queuePlayer?.pause()
        queuePlayer = nil
        playerLooper = nil
        
        // Reset audio session
        setupAudioSession()
        
        // Restart player
        if let quietToneURL = Bundle.main.url(forResource: "quiet_tone", withExtension: "m4a", subdirectory: "Sounds") {
            setupPlayer(url: quietToneURL)
        } else if let silenceURL = Bundle.main.url(forResource: "silence", withExtension: "mp3", subdirectory: "Sounds") {
            setupPlayer(url: silenceURL)
        }
        
        consecutiveFailures = 0
        print("[BackgroundKeepAlive] Playback restarted")
    }

    private func ensurePlaybackActive() {
        guard let queuePlayer = queuePlayer else {
            if isActive {
                // Player was lost - restart
                restartPlayback()
            }
            return
        }
        
        if queuePlayer.timeControlStatus != .playing {
            queuePlayer.play()
            print("[BackgroundKeepAlive] Resumed playback")
        }
    }
}

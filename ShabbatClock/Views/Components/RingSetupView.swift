import SwiftUI
import AVKit

/// Educational content explaining how the alarm auto-stop works and what the user
/// needs to do to get the cleanest experience (no audible vibration).
///
/// Used in:
/// - Settings → Ring Setup (full screen, NavigationLink)
/// - Onboarding → "How alarms ring" page (embedded)
/// - "Learn more" link from the alarm edit education card (sheet)
struct RingSetupView: View {
    /// Visual mode controls how the page is laid out:
    /// - `.standalone`: full-screen with its own background (Settings, Sheet)
    /// - `.embedded`: just the content, no background — caller provides one (onboarding)
    enum Mode {
        case standalone
        case embedded
    }

    let mode: Mode

    /// When set, displays the image full-screen with a dimmed background.
    /// Tap anywhere to dismiss. Used to let users zoom in on the small step screenshots.
    @State private var zoomedImage: String?

    var body: some View {
        Group {
            if mode == .standalone {
                ZStack {
                    LinearGradient.nightSky
                        .ignoresSafeArea()
                    scrollContent
                }
                .navigationTitle("Ring Setup")
                .navigationBarTitleDisplayMode(.inline)
            } else {
                scrollContent
            }
        }
        .overlay {
            if let image = zoomedImage {
                ImageZoomOverlay(imageName: image) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        zoomedImage = nil
                    }
                }
                .transition(.opacity)
            }
        }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                heroCard
                howItWorksCard
                instructionsCard
                videoCard
                bottomNote
            }
            .padding(.horizontal, 20)
            .padding(.top, mode == .standalone ? 16 : 0)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Hero

    private var heroCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 40))
                .foregroundStyle(.goldAccent)
                .padding(.top, 8)

            Text("Vibration-Free Auto-Stop")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.textPrimary)
                .multilineTextAlignment(.center)

            Text("Your alarm rings, then stops on its own — no vibration, no fuss. One quick setup makes it perfect for Shabbat.")
                .font(.system(size: 14))
                .foregroundStyle(.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .themeCard(cornerRadius: 16)
    }

    // MARK: - How it works

    private var howItWorksCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.accentPurple)
                Text("How auto-stop works")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.textPrimary)
            }

            Text("Your alarm rings, then ends automatically after the duration you pick. To make it truly silent, turn off Haptics in iOS Settings — otherwise iOS will keep vibrating for up to 15 minutes.")
                .font(.system(size: 13))
                .foregroundStyle(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .themeCard(cornerRadius: 14)
    }

    // MARK: - Instructions

    private var instructionsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "checklist")
                    .font(.system(size: 14))
                    .foregroundStyle(.goldAccent)
                Text("One-time setup")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.textPrimary)
            }

            // Recommended path: Silent mode
            VStack(alignment: .leading, spacing: 8) {
                Text("Recommended: Use Silent Mode")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.goldAccent)

                stepRow(number: 1, text: "Open **Settings → Sounds & Haptics**")
                stepRow(number: 2, text: "Tap **Haptics**")
                stepRow(number: 3, text: "Choose **Don't Play in Silent Mode**")
                stepRow(number: 4, text: "Before Shabbat, flip the silent switch on your iPhone")
            }
            .padding(.top, 4)

            // Screenshots showing the 3 settings steps. Hebrew variants used when app is in Hebrew.
            HStack(spacing: 8) {
                screenshotTile(image: localizedHapticsImage(1), label: "Step 1")
                screenshotTile(image: localizedHapticsImage(2), label: "Step 2")
                screenshotTile(image: localizedHapticsImage(3), label: "Step 3")
            }

            Divider().overlay(Color.surfaceBorder)

            // Alternative: Ring mode
            VStack(alignment: .leading, spacing: 6) {
                Text("Or: If you keep your phone in Ring Mode")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.textSecondary)
                Text("Choose **Don't Play** instead, so vibration is off in both modes.")
                    .font(.system(size: 12))
                    .foregroundStyle(.textSecondary.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Open Settings button
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "gear")
                        .font(.system(size: 13))
                    Text("Open Settings")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 11))
                }
                .foregroundStyle(.accentPurple)
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.accentPurple.opacity(0.12))
                )
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .themeCard(cornerRadius: 14)
    }

    /// Returns the asset name for the Nth haptics-settings screenshot, picking the
    /// Hebrew variant when the app is in Hebrew so the iOS UI shown matches the
    /// user's device language.
    private func localizedHapticsImage(_ step: Int) -> String {
        AppLanguage.current == .hebrew ? "hapticsHebrew\(step)" : "haptics\(step)"
    }

    private func screenshotTile(image: String, label: LocalizedStringKey) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) {
                zoomedImage = image
            }
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.surfaceBorder, lineWidth: 0.5)
                        )

                    // Subtle zoom indicator
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(Circle().fill(Color.black.opacity(0.5)))
                        .padding(4)
                }

                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.textSecondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func stepRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.accentPurple))

            Text(.init(text))
                .font(.system(size: 13))
                .foregroundStyle(.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Video

    private var videoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.accentPurple)
                Text("Visual walkthrough")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.textPrimary)
            }

            HapticsVideoPlayer()
                .frame(maxWidth: .infinity)
                .frame(height: 380)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .themeCard(cornerRadius: 14)
    }

    // MARK: - Bottom note

    private var bottomNote: some View {
        VStack(spacing: 4) {
            Text("Once your phone is set up, alarms will ring and auto-stop quietly — even when locked.")
                .font(.system(size: 11))
                .foregroundStyle(.textSecondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
        }
    }
}

// MARK: - Haptics Video Player

/// Plays the bundled `haptics` video on loop, muted, with a subtle fade at the
/// top edge to mask the iOS status bar visible in the source recording.
/// Uses the Hebrew variant when the app is in Hebrew so the iOS UI in the video
/// matches the user's device language.
struct HapticsVideoPlayer: View {
    @State private var player: AVPlayer?

    /// Asset name of the data asset to play. Picked at view creation time based on language.
    private let assetName: String

    init() {
        self.assetName = AppLanguage.current == .hebrew ? "hapticsHebrew" : "haptics"
    }

    var body: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player)
                    .disabled(true) // hide system controls; user can't pause/scrub
                    .onAppear {
                        player.play()
                    }
                    .onDisappear {
                        player.pause()
                    }
                    .overlay(alignment: .top) {
                        // Soft gradient at the top to mask any status bar visible in the recording
                        LinearGradient(
                            colors: [Color.surfaceCard, Color.surfaceCard.opacity(0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 40)
                        .allowsHitTesting(false)
                    }
            } else {
                // Placeholder while loading or if asset missing
                Color.surfaceSubtle
                    .overlay(
                        ProgressView()
                            .tint(.textSecondary)
                    )
            }
        }
        .task {
            await loadVideo()
        }
    }

    /// Loads the appropriate haptics data asset and prepares an AVPlayer that loops it.
    private func loadVideo() async {
        guard let dataAsset = NSDataAsset(name: assetName) else { return }

        // AVPlayer can't read directly from an in-memory Data; write to a temp file.
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("haptics-\(dataAsset.data.hashValue).mp4")
        if !FileManager.default.fileExists(atPath: tempURL.path) {
            try? dataAsset.data.write(to: tempURL)
        }

        let item = AVPlayerItem(url: tempURL)
        let avPlayer = AVPlayer(playerItem: item)
        avPlayer.isMuted = true
        avPlayer.actionAtItemEnd = .none

        // Loop on item end
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            avPlayer.seek(to: .zero)
            avPlayer.play()
        }

        await MainActor.run {
            self.player = avPlayer
        }
    }
}

// MARK: - Image Zoom Overlay

/// Full-screen image viewer with dimmed background. Tap anywhere or the X button
/// to dismiss. Supports pinch-to-zoom and drag-to-pan via SwiftUI's built-in gestures.
struct ImageZoomOverlay: View {
    let imageName: String
    let onDismiss: () -> Void

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            // Dimmed background — tap anywhere to dismiss
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }

            // The image, centered, with pinch + drag
            Image(imageName)
                .resizable()
                .scaledToFit()
                .padding(.horizontal, 20)
                .padding(.vertical, 60)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    SimultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = max(1, min(lastScale * value, 4))
                            }
                            .onEnded { _ in
                                lastScale = scale
                                if scale <= 1 {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        scale = 1
                                        lastScale = 1
                                        offset = .zero
                                        lastOffset = .zero
                                    }
                                }
                            },
                        DragGesture()
                            .onChanged { value in
                                guard scale > 1 else { return }
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                            .onEnded { _ in
                                lastOffset = offset
                            }
                    )
                )
                .onTapGesture(count: 2) {
                    // Double-tap to toggle zoom
                    withAnimation(.easeInOut(duration: 0.25)) {
                        if scale > 1 {
                            scale = 1
                            lastScale = 1
                            offset = .zero
                            lastOffset = .zero
                        } else {
                            scale = 2
                            lastScale = 2
                        }
                    }
                }

            // Close button (top-right)
            VStack {
                HStack {
                    Spacer()
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.black.opacity(0.6)))
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 16)
                }
                Spacer()
            }
        }
    }
}

// MARK: - Preview

#Preview("Standalone") {
    NavigationStack {
        RingSetupView(mode: .standalone)
    }
    .environment(AlarmKitService.shared)
}

#Preview("Embedded") {
    ZStack {
        LinearGradient.nightSky.ignoresSafeArea()
        RingSetupView(mode: .embedded)
    }
}

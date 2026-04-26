import SwiftUI
import AlarmKit

/// First-launch onboarding flow. Introduces the app and requests permissions in context.
/// Shows once — tracked via @AppStorage("hasCompletedOnboarding").
///
/// Order: Welcome → Alarms (core) → Ring Setup (vibration education) → Notifications (pre-Shabbat reminder) → Location (nice-to-have)
struct OnboardingView: View {
    @Environment(AlarmKitService.self) private var alarmService
    @StateObject private var locationManager = LocationManager.shared

    let onComplete: () -> Void

    @State private var currentPage: Int = 0
    @State private var zoomedImage: String?
    /// Mute state for the onboarding ambient track. Persisted so the choice
    /// carries over if the user re-enters the flow (debug reset, reinstall).
    @AppStorage("onboardingMusicMuted") private var isMusicMuted = false

    private let totalPages = 5

    /// Background music track played during onboarding.
    private var onboardingMusic: AlarmSound? {
        AlarmSound.sound(byId: "shalom-aleichem")
    }

    var body: some View {
        ZStack {
            LinearGradient.nightSky
                .ignoresSafeArea()

            TabView(selection: $currentPage) {
                welcomePage.tag(0)
                alarmsPage.tag(1)
                ringSetupPage.tag(2)
                notificationsPage.tag(3)
                locationPage.tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.3), value: currentPage)
            .onAppear { Analytics.track(.onboardingStarted) }
            .onChange(of: currentPage) { _, new in
                let page: AnalyticsEvent.OnboardingPage
                switch new {
                case 0: page = .welcome
                case 1: page = .alarms
                case 2: page = .ringSetup
                case 3: page = .notifications
                case 4: page = .location
                default: return
                }
                Analytics.track(.onboardingPageViewed(page: page))
            }

            // Page indicator at bottom
            VStack {
                Spacer()
                pageIndicator
                    .padding(.bottom, 16)
            }

            // Mute toggle — top trailing. Respects RTL via .topTrailing alignment.
            VStack {
                HStack {
                    Spacer()
                    muteButton
                        .padding(.top, 8)
                        .padding(.trailing, 16)
                }
                Spacer()
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
        .onAppear { startMusicIfNeeded() }
        .onDisappear { AudioManager.shared.stopBackgroundMusic() }
        .onChange(of: isMusicMuted) { _, muted in
            if muted {
                AudioManager.shared.stopBackgroundMusic()
            } else {
                startMusicIfNeeded()
            }
        }
    }

    /// Starts the ambient onboarding music if not muted and not already playing.
    private func startMusicIfNeeded() {
        guard !isMusicMuted else { return }
        guard let sound = onboardingMusic else { return }
        AudioManager.shared.startBackgroundMusic(sound: sound)
    }

    // MARK: - Mute Toggle

    private var muteButton: some View {
        Button {
            isMusicMuted.toggle()
        } label: {
            Image(systemName: isMusicMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.textSecondary)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(Color.surfaceCard.opacity(0.5))
                        .overlay(
                            Circle()
                                .stroke(Color.surfaceBorder, lineWidth: 0.5)
                        )
                )
        }
        .accessibilityLabel(Text(isMusicMuted ? "Unmute music" : "Mute music"))
    }

    // MARK: - Page 1: Welcome

    private var welcomePage: some View {
        OnboardingPage(
            icon: "alarm.waves.left.and.right",
            iconColor: .goldAccent,
            headline: "Shabbat Clock",
            subtitle: "The alarm clock designed\nfor Shabbat.",
            details: "Wake up for tefilah with traditional melodies. Put your phone down — we'll handle the rest.",
            buttonTitle: "Get Started",
            action: { advanceTo(1) }
        )
    }

    // MARK: - Page 2: Alarms

    private var alarmsPage: some View {
        OnboardingPage(
            icon: "alarm.fill",
            iconColor: .goldAccent,
            headline: "Reliable Alarms",
            subtitle: "Silent mode? Do Not Disturb?\nWe ring anyway.",
            details: "One quick permission and your Shabbat alarm works like the built-in Clock app — loud, on time, every time.",
            deniedDetails: "Alarms are turned off. You can enable them anytime in Settings → Shabbat Clock → Alarms.",
            isAuthorized: alarmService.isAuthorized,
            isDenied: alarmService.isAlarmDenied,
            buttonTitle: "Allow Alarms",
            action: {
                if alarmService.isAuthorized {
                    // Already authorized — green-checkmark state was tapped; advance.
                    advanceTo(2)
                } else {
                    Analytics.track(.onboardingPermissionPrompted(permission: .alarms))
                    Task {
                        await alarmService.requestAuthorization()
                        // Don't auto-advance — let the page rebind to the authorized or
                        // denied state so the user sees the outcome, then taps Continue.
                        if alarmService.isAuthorized {
                            Analytics.track(.onboardingPermissionGranted(permission: .alarms))
                        } else {
                            Analytics.track(.onboardingPermissionDenied(permission: .alarms))
                        }
                    }
                }
            },
            continueAction: { advanceTo(2) }
        )
    }

    // MARK: - Page 3: Ring Setup (vibration education)

    private var ringSetupPage: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 24)

            // Icon
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 44))
                .foregroundStyle(.goldAccent)
                .padding(.bottom, 12)

            // Headline
            Text("Vibration-Free Auto-Stop")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 4)

            // Subtitle
            Text("One iPhone setting makes\nShabbat alarms perfect.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 16)

            // Screenshots showing the 3 steps in iOS Settings
            // Use Hebrew screenshots when the app is in Hebrew so the iOS UI shown matches the user's device language.
            HStack(spacing: 8) {
                onboardingScreenshot(image: localizedHapticsImage(1), caption: "Sounds & Haptics")
                onboardingScreenshot(image: localizedHapticsImage(2), caption: "Tap Haptics")
                onboardingScreenshot(image: localizedHapticsImage(3), caption: "Don't Play in Silent")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)

            // Important final step — silent switch must be ON for the setting to take effect
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "iphone.gen3.radiowaves.left.and.right.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.goldAccent)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Then switch your iPhone to Silent Mode")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.textPrimary)
                    Text("Use the silent switch on the side of your phone before Shabbat.")
                        .font(.system(size: 11))
                        .foregroundStyle(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.goldAccent.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.goldAccent.opacity(0.25), lineWidth: 0.5)
                    )
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Text("You can do this anytime — we'll remind you in Settings → Ring Setup.")
                .font(AppFont.body(12))
                .foregroundStyle(.textSecondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            // CTA — open Settings
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "gear")
                        .font(.system(size: 16))
                    Text("Open Settings")
                        .font(.system(size: 17, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.accentPurple)
                        .shadow(color: Color.accentPurple.opacity(0.4), radius: 12, y: 4)
                )
            }
            .padding(.horizontal, 32)

            // Skip / Continue
            Button { advanceTo(3) } label: {
                Text("Continue")
                    .font(AppFont.body(14))
                    .foregroundStyle(.textSecondary)
            }
            .padding(.top, 14)

            Spacer().frame(height: 50)
        }
    }

    /// Returns the asset name for the Nth haptics-settings screenshot, picking the
    /// Hebrew variant when the app is set to Hebrew so the iOS UI shown matches the
    /// user's device language.
    private func localizedHapticsImage(_ step: Int) -> String {
        AppLanguage.current == .hebrew ? "hapticsHebrew\(step)" : "haptics\(step)"
    }

    /// One screenshot tile in the onboarding ring-setup page. Tap to zoom.
    private func onboardingScreenshot(image: String, caption: String) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) {
                zoomedImage = image
            }
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Image(image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.surfaceBorder, lineWidth: 0.5)
                        )

                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(Circle().fill(Color.black.opacity(0.5)))
                        .padding(4)
                }

                Text(caption)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Page 4: Notifications

    private var notificationsPage: some View {
        OnboardingPage(
            icon: "bell.badge.fill",
            iconColor: .goldAccent,
            headline: "Pre-Shabbat Reminder",
            subtitle: "Get a heads-up before\nShabbat starts.",
            details: "We'll remind you Friday afternoon to review your alarms. You can change the timing anytime in Settings.",
            deniedDetails: "Notifications are turned off. Enable them in Settings → Shabbat Clock → Notifications to get your pre-Shabbat reminder.",
            isAuthorized: alarmService.isNotificationAuthorized,
            isDenied: alarmService.isNotificationDenied,
            buttonTitle: "Allow Notifications",
            action: {
                if alarmService.isNotificationAuthorized {
                    // Already authorized — green-checkmark state was tapped; advance.
                    advanceTo(4)
                } else {
                    Analytics.track(.onboardingPermissionPrompted(permission: .notifications))
                    Task {
                        await alarmService.requestNotificationAuthorization()
                        // Don't auto-advance — let the page rebind so the user sees the
                        // authorized or denied state and taps Continue themselves.
                        if alarmService.isNotificationAuthorized {
                            Analytics.track(.onboardingPermissionGranted(permission: .notifications))
                        } else {
                            Analytics.track(.onboardingPermissionDenied(permission: .notifications))
                        }
                    }
                }
            },
            continueAction: { advanceTo(4) }
        )
    }

    // MARK: - Page 5: Location

    private var locationPage: some View {
        OnboardingPage(
            icon: "location.fill",
            iconColor: .accentPurple,
            headline: "Shabbat Times",
            subtitle: "Precise times\nfor your location.",
            details: "Get precise candle lighting and havdalah times based on where you are. You can also choose your city manually.",
            deniedDetails: "Location is turned off. Enable it in Settings → Shabbat Clock → Location, or choose your city manually from the main screen.",
            isAuthorized: locationManager.isAuthorized,
            isDenied: locationManager.authorizationStatus == .denied
                || locationManager.authorizationStatus == .restricted,
            buttonTitle: "Allow Location",
            action: {
                if locationManager.isAuthorized {
                    completeOnboarding()
                } else {
                    Analytics.track(.onboardingPermissionPrompted(permission: .location))
                    locationManager.requestPermission()
                    // Wait for the system dialog to resolve before deciding next step.
                    // The page rebinds via authorizationStatus observation and will show
                    // either the authorized checkmark or the Open Settings denied state.
                    // Granted/denied tracking happens via .onChange below.
                }
            },
            continueAction: { completeOnboarding() },
            isFinal: true
        )
        .onChange(of: locationManager.authorizationStatus) { _, new in
            switch new {
            case .authorizedWhenInUse, .authorizedAlways:
                Analytics.track(.onboardingPermissionGranted(permission: .location))
            case .denied, .restricted:
                Analytics.track(.onboardingPermissionDenied(permission: .location))
            default: break
            }
        }
    }

    // MARK: - Page Indicator

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalPages, id: \.self) { index in
                Circle()
                    .fill(index == currentPage ? Color.goldAccent : Color.textSecondary.opacity(0.3))
                    .frame(width: index == currentPage ? 10 : 7, height: index == currentPage ? 10 : 7)
                    .animation(.easeInOut(duration: 0.2), value: currentPage)
            }
        }
    }

    // MARK: - Navigation

    private func advanceTo(_ page: Int) {
        withAnimation {
            currentPage = page
        }
    }

    private func completeOnboarding() {
        Analytics.track(.onboardingCompleted(
            alarmAuthorized: alarmService.isAuthorized,
            notificationsAuthorized: alarmService.isNotificationAuthorized,
            locationAuthorized: locationManager.isAuthorized
        ))
        onComplete()
    }
}

// MARK: - Onboarding Page (Reusable)

/// A single page in the onboarding flow with bold visual hierarchy.
///
/// Renders three states for permission pages (Apple Guideline 5.1.1(iv) compliant):
/// - **Not requested yet**: primary button triggers the system permission dialog.
/// - **Authorized**: green checkmark state, primary button advances to next page.
/// - **Denied**: Open Settings primary button (deep-links to iOS Settings), small
///   Continue link below to advance past the page. There is no skip button that
///   precedes the system dialog — the only way to bypass is through Apple's dialog.
///
/// For non-permission pages (Welcome, Ring Setup), pass `isAuthorized: true` and
/// a plain action — the page behaves like a standard continue-only screen.
private struct OnboardingPage: View {
    let icon: String
    let iconColor: Color
    let headline: LocalizedStringResource
    let subtitle: LocalizedStringResource
    let details: LocalizedStringResource
    /// Alternate detail copy shown when the permission has been denied.
    var deniedDetails: LocalizedStringResource? = nil
    var isAuthorized: Bool = false
    var isDenied: Bool = false
    var buttonTitle: LocalizedStringResource = "Continue"
    /// Primary action:
    /// - On first view: triggers the system permission dialog (caller owns this).
    /// - When authorized: advances to the next page.
    /// - When denied: unused (Open Settings is handled internally).
    let action: () -> Void
    /// Called when the user taps the small "Continue" link in the denied state
    /// to advance past this page. Required for permission pages.
    var continueAction: (() -> Void)? = nil
    var isFinal: Bool = false

    /// Copy shown under the subtitle — swaps to denied copy when permission was denied.
    private var effectiveDetails: LocalizedStringResource {
        if isDenied, let deniedDetails { return deniedDetails }
        return details
    }

    /// The primary CTA title based on state.
    private var primaryTitle: LocalizedStringResource {
        if isDenied { return "Open Settings" }
        if isAuthorized { return isFinal ? "Done" : "Continue" }
        return buttonTitle
    }

    /// System-image name shown to the left of the primary CTA title.
    private var primaryIcon: String? {
        if isDenied { return "gear" }
        if isAuthorized { return "checkmark.circle.fill" }
        return nil
    }

    /// Background color for the primary CTA.
    private var primaryFill: Color {
        if isAuthorized { return Color.green.opacity(0.8) }
        return Color.accentPurple
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Large icon
            Image(systemName: icon)
                .font(.system(size: 72))
                .foregroundStyle(iconColor)
                .padding(.bottom, 28)

            // Bold headline
            Text(headline)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 8)

            // Subtitle — the key message
            Text(subtitle)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 20)

            // Details — supporting context (swaps to denied copy when applicable)
            Text(effectiveDetails)
                .font(AppFont.body(15))
                .foregroundStyle(.textSecondary.opacity(0.8))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 40)

            Spacer()

            // Primary CTA — unmissable
            Button {
                if isDenied {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } else {
                    action()
                }
            } label: {
                HStack(spacing: 8) {
                    if let primaryIcon {
                        Image(systemName: primaryIcon)
                            .font(.system(size: 18))
                    }
                    Text(primaryTitle)
                        .font(.system(size: 18, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(primaryFill)
                        .shadow(color: primaryFill.opacity(0.4), radius: 12, y: 4)
                )
            }
            .padding(.horizontal, 32)

            // Secondary "Continue" link — shown ONLY after user responded to the system
            // permission dialog with "Deny". This is the documented-compliant escape hatch:
            // Apple's rule (5.1.1(iv)) forbids a skip button BEFORE the system dialog, not after.
            if isDenied, let continueAction {
                Button(action: continueAction) {
                    Text("Continue")
                        .font(AppFont.body(14))
                        .foregroundStyle(.textSecondary)
                }
                .padding(.top, 14)
            }

            Spacer()
                .frame(height: 50)
        }
    }
}

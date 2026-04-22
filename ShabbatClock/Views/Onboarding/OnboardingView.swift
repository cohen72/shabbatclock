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

    private let totalPages = 5

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

            // Page indicator at bottom
            VStack {
                Spacer()
                pageIndicator
                    .padding(.bottom, 16)
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
            buttonTitle: alarmService.isAuthorized ? "Alarms Enabled" : "Enable Alarms",
            buttonIcon: alarmService.isAuthorized ? "checkmark.circle.fill" : nil,
            isAlreadyGranted: alarmService.isAuthorized,
            action: {
                if alarmService.isAuthorized {
                    advanceTo(2)
                } else {
                    Task {
                        await alarmService.requestAuthorization()
                        advanceTo(2)
                    }
                }
            },
            skipAction: { advanceTo(2) }
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
            Text("Silent Auto-Stop")
                .font(.system(size: 26, weight: .bold))
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
            HStack(spacing: 8) {
                onboardingScreenshot(image: "haptics1", caption: "Sounds & Haptics")
                onboardingScreenshot(image: "haptics2", caption: "Tap Haptics")
                onboardingScreenshot(image: "haptics3", caption: "Don't Play in Silent")
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

    // MARK: - Page 4: Notifications (custom layout for urgency)

    private var notificationsPage: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 72))
                .foregroundStyle(.goldAccent)
                .padding(.bottom, 28)

            // Headline
            Text("Pre-Shabbat Reminder")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 8)

            // Subtitle
            Text("Get a heads-up before\nShabbat starts.")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 20)

            // Details
            Text("We'll remind you Friday afternoon to review your alarms. You can change the timing anytime in Settings.")
                .font(AppFont.body(15))
                .foregroundStyle(.textSecondary.opacity(0.8))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 40)
                .padding(.bottom, 20)

            Spacer()

            // CTA
            Button {
                if alarmService.isNotificationAuthorized {
                    advanceTo(4)
                } else {
                    Task {
                        await alarmService.requestNotificationAuthorization()
                        advanceTo(4)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if alarmService.isNotificationAuthorized {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                    }
                    Text(alarmService.isNotificationAuthorized
                         ? "Alerts Enabled" : "Allow Notifications")
                        .font(.system(size: 18, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(alarmService.isNotificationAuthorized
                              ? Color.green.opacity(0.8) : Color.accentPurple)
                        .shadow(color: (alarmService.isNotificationAuthorized
                                        ? Color.green : Color.accentPurple).opacity(0.4),
                                radius: 12, y: 4)
                )
            }
            .padding(.horizontal, 32)

            // Skip
            Button { advanceTo(4) } label: {
                Text("Not Now")
                    .font(AppFont.body(14))
                    .foregroundStyle(.textSecondary)
            }
            .padding(.top, 14)

            Spacer()
                .frame(height: 50)
        }
    }

    // MARK: - Page 4: Location

    private var locationPage: some View {
        OnboardingPage(
            icon: "location.fill",
            iconColor: .accentPurple,
            headline: "Prayer Times",
            subtitle: "Accurate zmanim\nfor your location.",
            details: "Get precise candle lighting and havdalah times based on where you are. You can also choose your city manually.",
            buttonTitle: locationManager.isAuthorized ? "Location Enabled" : "Enable Location",
            buttonIcon: locationManager.isAuthorized ? "checkmark.circle.fill" : nil,
            isAlreadyGranted: locationManager.isAuthorized,
            action: {
                if locationManager.isAuthorized {
                    completeOnboarding()
                } else {
                    locationManager.requestPermission()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        completeOnboarding()
                    }
                }
            },
            skipAction: { completeOnboarding() },
            isFinal: true
        )
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
        onComplete()
    }
}

// MARK: - Onboarding Page (Reusable)

/// A single page in the onboarding flow with bold visual hierarchy.
private struct OnboardingPage: View {
    let icon: String
    let iconColor: Color
    let headline: LocalizedStringResource
    let subtitle: LocalizedStringResource
    let details: LocalizedStringResource
    let buttonTitle: LocalizedStringResource
    var buttonIcon: String? = nil
    var isAlreadyGranted: Bool = false
    let action: () -> Void
    var skipAction: (() -> Void)? = nil
    var isFinal: Bool = false

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

            // Details — supporting context
            Text(details)
                .font(AppFont.body(15))
                .foregroundStyle(.textSecondary.opacity(0.8))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 40)

            Spacer()

            // CTA button — large, prominent, unmissable
            Button(action: action) {
                HStack(spacing: 8) {
                    if let buttonIcon {
                        Image(systemName: buttonIcon)
                            .font(.system(size: 18))
                    }
                    Text(buttonTitle)
                        .font(.system(size: 18, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(isAlreadyGranted ? Color.green.opacity(0.8) : Color.accentPurple)
                        .shadow(color: (isAlreadyGranted
                                        ? Color.green : Color.accentPurple).opacity(0.4),
                                radius: 12, y: 4)
                )
            }
            .padding(.horizontal, 32)

            // Skip
            if let skipAction {
                Button(action: skipAction) {
                    Text(isFinal ? "Maybe Later" : "Not Now")
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

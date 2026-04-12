import SwiftUI
import AlarmKit

/// First-launch onboarding flow. Introduces the app and requests permissions in context.
/// Shows once — tracked via @AppStorage("hasCompletedOnboarding").
/// Each page educates the user before triggering the system permission dialog.
struct OnboardingView: View {
    @Environment(AlarmKitService.self) private var alarmService
    @StateObject private var locationManager = LocationManager.shared

    let onComplete: () -> Void

    @State private var currentPage: Int = 0

    private let totalPages = 4

    var body: some View {
        ZStack {
            LinearGradient.nightSky
                .ignoresSafeArea()

            TabView(selection: $currentPage) {
                welcomePage.tag(0)
                locationPage.tag(1)
                alarmsPage.tag(2)
                notificationsPage.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.3), value: currentPage)

            // Custom page indicator + progress
            VStack {
                Spacer()
                pageIndicator
                    .padding(.bottom, 20)
            }
        }
    }

    // MARK: - Page 1: Welcome

    private var welcomePage: some View {
        OnboardingPage(
            icon: "alarm.waves.left.and.right",
            iconColor: .goldAccent,
            title: "Welcome to Shabbat Clock",
            message: "The alarm clock designed for Shabbat observers. Set alarms for tefilah, wake up to traditional melodies, and put your phone down for all of Shabbat.",
            buttonTitle: "Get Started",
            action: { advanceTo(1) }
        )
    }

    // MARK: - Page 2: Location

    private var locationPage: some View {
        OnboardingPage(
            icon: "location.fill",
            iconColor: .accentPurple,
            title: "Accurate Prayer Times",
            message: "Shabbat Clock uses your location to calculate precise zmanim for your area — including candle lighting and havdalah times.",
            buttonTitle: "Enable Location",
            action: {
                locationManager.requestPermission()
                // Short delay for system dialog, then advance
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    advanceTo(2)
                }
            },
            skipAction: { advanceTo(2) }
        )
    }

    // MARK: - Page 3: Alarms

    private var alarmsPage: some View {
        OnboardingPage(
            icon: "alarm.fill",
            iconColor: .goldAccent,
            title: "Shabbat Alarms",
            message: "Alarms will sound even when your phone is on Do Not Disturb — so you can put your phone down for all of Shabbat and still wake up for tefilah.",
            buttonTitle: "Enable Alarms",
            action: {
                Task {
                    await alarmService.requestAuthorization()
                    advanceTo(3)
                }
            },
            skipAction: { advanceTo(3) }
        )
    }

    // MARK: - Page 4: Notifications

    private var notificationsPage: some View {
        OnboardingPage(
            icon: "bell.fill",
            iconColor: .goldAccent,
            title: "Alarm Notifications",
            message: "Notifications allow your alarm to automatically stop after the duration you set — so you don't need to touch your phone on Shabbat.",
            buttonTitle: "Enable Notifications",
            action: {
                Task {
                    await alarmService.requestNotificationAuthorization()
                    completeOnboarding()
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

// MARK: - Onboarding Page

/// A single page in the onboarding flow. Reuses the same visual language as PermissionPromptView
/// but optimized for the paged TabView context.
private struct OnboardingPage: View {
    let icon: String
    let iconColor: Color
    let title: LocalizedStringResource
    let message: LocalizedStringResource
    let buttonTitle: LocalizedStringResource
    let action: () -> Void
    var skipAction: (() -> Void)? = nil
    var isFinal: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 80)

            // Icon
            Image(systemName: icon)
                .font(.system(size: 64))
                .foregroundStyle(iconColor)
                .padding(.bottom, 32)

            // Title
            Text(title)
                .font(AppFont.header(24))
                .foregroundStyle(.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 16)

            // Message
            Text(message)
                .font(AppFont.body(15))
                .foregroundStyle(.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 40)

            Spacer()

            // Action button
            Button(action: action) {
                Text(buttonTitle)
                    .font(AppFont.body(16))
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.accentPurple)
                    )
            }
            .padding(.horizontal, 32)

            // Skip / Not Now
            if let skipAction {
                Button(action: skipAction) {
                    Text(isFinal ? "Maybe Later" : "Not Now")
                        .font(AppFont.body(14))
                        .foregroundStyle(.textSecondary)
                }
                .padding(.top, 16)
            }

            Spacer()
                .frame(height: 60)
        }
    }
}

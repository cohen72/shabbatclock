import SwiftUI

/// A pre-permission education screen shown before the system permission dialog.
/// Explains to the user why we need the permission, in context, before triggering the system alert.
struct PermissionPromptView: View {
    let icon: String
    let iconColor: Color
    let title: LocalizedStringResource
    let message: LocalizedStringResource
    let continueTitle: LocalizedStringResource
    let onContinue: () -> Void
    let onSkip: (() -> Void)?

    init(
        icon: String,
        iconColor: Color = .accentPurple,
        title: LocalizedStringResource,
        message: LocalizedStringResource,
        continueTitle: LocalizedStringResource = "Continue",
        onContinue: @escaping () -> Void,
        onSkip: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.message = message
        self.continueTitle = continueTitle
        self.onContinue = onContinue
        self.onSkip = onSkip
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon
            Image(systemName: icon)
                .font(.system(size: 56))
                .foregroundStyle(iconColor)
                .padding(.bottom, 24)

            // Title
            Text(title)
                .font(AppFont.header(22))
                .foregroundStyle(.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 12)

            // Message
            Text(message)
                .font(AppFont.body(15))
                .foregroundStyle(.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 32)

            Spacer()

            // Continue button
            Button {
                onContinue()
            } label: {
                Text(continueTitle)
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

            // Skip button
            if let onSkip {
                Button {
                    onSkip()
                } label: {
                    Text("Not Now")
                        .font(AppFont.body(14))
                        .foregroundStyle(.textSecondary)
                }
                .padding(.top, 16)
            }

            Spacer()
                .frame(height: 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient.nightSky.ignoresSafeArea())
    }
}

// MARK: - Predefined Permission Prompts

extension PermissionPromptView {

    /// Location permission — shown before the system "Allow Location" dialog.
    static func location(onContinue: @escaping () -> Void, onSkip: (() -> Void)? = nil) -> PermissionPromptView {
        PermissionPromptView(
            icon: "location.fill",
            iconColor: .accentPurple,
            title: "Accurate Prayer Times",
            message: "Shabbat Clock uses your location to calculate precise zmanim (halachic times) for your area — including candle lighting and havdalah times.",
            continueTitle: "Enable Location",
            onContinue: onContinue,
            onSkip: onSkip
        )
    }

    /// AlarmKit permission — shown before the system "Allow Alarms" dialog.
    static func alarms(onContinue: @escaping () -> Void, onSkip: (() -> Void)? = nil) -> PermissionPromptView {
        PermissionPromptView(
            icon: "alarm.fill",
            iconColor: .goldAccent,
            title: "Shabbat Alarms",
            message: "Shabbat Clock needs alarm access to wake you for tefilah. Alarms will sound even when your phone is on Do Not Disturb — so you can put your phone down for all of Shabbat.",
            continueTitle: "Enable Alarms",
            onContinue: onContinue,
            onSkip: onSkip
        )
    }

    /// Notification permission — shown before the system "Allow Notifications" dialog.
    static func notifications(onContinue: @escaping () -> Void, onSkip: (() -> Void)? = nil) -> PermissionPromptView {
        PermissionPromptView(
            icon: "bell.fill",
            iconColor: .goldAccent,
            title: "Alarm Notifications",
            message: "Notifications allow Shabbat Clock to automatically stop your alarm after the duration you set — so you don't need to touch your phone on Shabbat.",
            continueTitle: "Enable Notifications",
            onContinue: onContinue,
            onSkip: onSkip
        )
    }
}

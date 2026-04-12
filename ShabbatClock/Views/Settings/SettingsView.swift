import SwiftUI
import StoreKit

/// App settings view.
struct SettingsView: View {
    @AppStorage("isPremium") private var isPremium = false
    @AppStorage("defaultSound") private var defaultSound = "Lecha Dodi"

    @State private var showingPremium = false
    @State private var showingAbout = false

    var body: some View {
        NavigationStack {
        ZStack {
            LinearGradient.nightSky
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                Text("Settings")
                    .font(AppFont.header(28))
                    .foregroundStyle(.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 24)

                ScrollView {
                    VStack(spacing: 24) {
                        // Premium section
                        premiumSection

                        // Defaults section
                        defaultsSection

                        // About section
                        aboutSection
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 120)
                }
            }
        }
        .sheet(isPresented: $showingPremium) {
            PremiumView()
        }
        .sheet(isPresented: $showingAbout) {
            AboutView()
        }
        .toolbar(.hidden)
        } // NavigationStack
    }

    // MARK: - Premium Section

    private var premiumSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Premium", icon: "star.fill")

            if isPremium {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Premium Active")
                            .font(AppFont.body())
                            .foregroundStyle(.textPrimary)
                        Text("Thank you for your support!")
                            .font(AppFont.caption(12))
                            .foregroundStyle(.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.goldAccent)
                }
                .padding(16)
                .settingsCard()
            } else {
                Button {
                    showingPremium = true
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Upgrade to Premium")
                                .font(AppFont.body())
                                .foregroundStyle(.textPrimary)
                            Text("Unlimited alarms, all sounds")
                                .font(AppFont.caption(12))
                                .foregroundStyle(.textSecondary)
                        }

                        Spacer()

                        Text("$4.99")
                            .font(AppFont.body())
                            .foregroundStyle(.goldAccent)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 14))
                            .foregroundStyle(.textSecondary)
                    }
                    .padding(16)
                    .settingsCard()
                }
            }
        }
    }

    // MARK: - Defaults Section

    private var defaultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Defaults", icon: "slider.horizontal.3")

            NavigationLink {
                DefaultSoundPicker(selectedSound: $defaultSound)
            } label: {
                HStack {
                    Text("Default Sound")
                        .font(AppFont.body())
                        .foregroundStyle(.textPrimary)

                    Spacer()

                    Text(defaultSound)
                        .font(AppFont.body(14))
                        .foregroundStyle(.textSecondary)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14))
                        .foregroundStyle(.textSecondary)
                }
                .padding(16)
                .settingsCard()
            }
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "About", icon: "info.circle")

            VStack(spacing: 1) {
                // Version
                settingsRow {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .font(AppFont.body(14))
                        .foregroundStyle(.textSecondary)
                }

                // About
                settingsRow {
                    Button {
                        showingAbout = true
                    } label: {
                        HStack {
                            Text("About Shabbat Clock")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14))
                                .foregroundStyle(.textSecondary)
                        }
                    }
                }

                // Contact
                settingsRow {
                    Link(destination: URL(string: "mailto:support@shabbatclock.app")!) {
                        HStack {
                            Text("Contact Support")
                            Spacer()
                            Image(systemName: "envelope")
                                .font(.system(size: 14))
                                .foregroundStyle(.textSecondary)
                        }
                    }
                }

                // Rate app
                settingsRow {
                    Button {
                        requestReview()
                    } label: {
                        HStack {
                            Text("Rate the App")
                            Spacer()
                            Image(systemName: "star")
                                .font(.system(size: 14))
                                .foregroundStyle(.goldAccent)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
            )
        }
    }

    @ViewBuilder
    private func settingsRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack {
            content()
        }
        .font(AppFont.body())
        .foregroundStyle(.textPrimary)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.07))
    }

    private func requestReview() {
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            SKStoreReviewController.requestReview(in: scene)
        }
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.accentPurple)
            Text(title)
                .font(AppFont.caption(12))
                .foregroundStyle(.textSecondary)
        }
    }
}

// MARK: - Default Sound Picker

struct DefaultSoundPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedSound: String
    @AppStorage("isPremium") private var isPremium = false

    var body: some View {
        ZStack {
            LinearGradient.nightSky
                .ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(AlarmSound.allSounds.filter { isPremium || !$0.isPremium }) { sound in
                        Button {
                            selectedSound = sound.name
                            dismiss()
                        } label: {
                            HStack {
                                Text(sound.name)
                                    .font(AppFont.body())
                                    .foregroundStyle(.textPrimary)

                                Spacer()

                                if selectedSound == sound.name {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.accentPurple)
                                }
                            }
                            .padding(16)
                            .background(Color.white.opacity(0.05))
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(24)
            }
        }
        .navigationTitle("Default Sound")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - About View

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LinearGradient.nightSky
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Handle
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 40, height: 4)
                    .padding(.top, 12)

                // App icon placeholder
                Image(systemName: "alarm.waves.left.and.right")
                    .font(.system(size: 60))
                    .foregroundStyle(.goldAccent)
                    .padding(.top, 24)

                Text("Shabbat Clock")
                    .font(AppFont.header(28))
                    .foregroundStyle(.textPrimary)

                Text("The alarm clock designed for\nShabbat observers")
                    .font(AppFont.body())
                    .foregroundStyle(.textSecondary)
                    .multilineTextAlignment(.center)

                Spacer()

                VStack(spacing: 8) {
                    Text("Built with ❤️ for the Jewish community")
                        .font(AppFont.caption(13))
                        .foregroundStyle(.textSecondary)

                    Text("© 2024 Shabbat Clock")
                        .font(AppFont.caption(12))
                        .foregroundStyle(.textSecondary.opacity(0.6))
                }
                .padding(.bottom, 40)
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
}

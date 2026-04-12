import SwiftUI

/// App settings view.
struct SettingsView: View {
    @Environment(\.requestReview) private var requestReview
    @AppStorage("isPremium") private var isPremium = false
    @AppStorage("defaultSound") private var defaultSound = "Lecha Dodi"
    @AppStorage("appearanceMode") private var appearanceMode: String = AppearanceMode.system.rawValue
    @AppStorage("appLanguage") private var appLanguage: String = AppLanguage.system.rawValue

    @StateObject private var locationManager = LocationManager.shared
    @State private var showingPremium = false
    @State private var showingAbout = false
    @State private var showingCitySearch = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient.nightSky
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Location section
                        locationSection

                        // Appearance section
                        appearanceSection

                        // Language section
                        languageSection

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
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showingPremium) {
                PremiumView()
                    .applyLanguageOverride(AppLanguage.current)
            }
            .sheet(isPresented: $showingAbout) {
                AboutView()
                    .applyLanguageOverride(AppLanguage.current)
            }
            .sheet(isPresented: $showingCitySearch) {
                CitySearchView()
                    .applyLanguageOverride(AppLanguage.current)
            }
        }
    }

    // MARK: - Location Section

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Location", icon: "location.fill")

            Button {
                showingCitySearch = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: locationManager.isUsingManualLocation ? "mappin.circle.fill" : "location.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.accentPurple)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Current City")
                            .font(AppFont.body())
                            .foregroundStyle(.textPrimary)

                        Group {
                            if locationManager.locationName == "__unknown__" {
                                Text("Unknown Location")
                            } else {
                                Text(locationManager.locationName)
                            }
                        }
                        .font(AppFont.caption(12))
                        .foregroundStyle(.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.forward")
                        .font(.system(size: 14))
                        .foregroundStyle(.textSecondary)
                }
                .padding(16)
                .settingsCard()
            }
        }
    }

    // MARK: - Appearance Section

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Appearance", icon: "circle.lefthalf.filled")

            VStack(spacing: 0) {
                HStack {
                    Text("Theme")
                        .font(AppFont.body())
                        .foregroundStyle(.textPrimary)

                    Spacer()

                    Picker("Theme", selection: $appearanceMode) {
                        Text("System").tag(AppearanceMode.system.rawValue)
                        Text("Light").tag(AppearanceMode.light.rawValue)
                        Text("Dark").tag(AppearanceMode.dark.rawValue)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
                .padding(16)
            }
            .settingsCard()
        }
    }

    // MARK: - Language Section

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Language", icon: "globe")

            VStack(spacing: 0) {
                HStack {
                    Text("Language")
                        .font(AppFont.body())
                        .foregroundStyle(.textPrimary)

                    Spacer()

                    Picker("Language", selection: $appLanguage) {
                        Text("System").tag(AppLanguage.system.rawValue)
                        Text(verbatim: "English").tag(AppLanguage.english.rawValue)
                        Text(verbatim: "עברית").tag(AppLanguage.hebrew.rawValue)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
                .padding(16)
            }
            .settingsCard()
        }
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

                        Image(systemName: "chevron.forward")
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
                SoundPickerView(selectedSoundName: $defaultSound)
            } label: {
                HStack {
                    Text("Default Sound")
                        .font(AppFont.body())
                        .foregroundStyle(.textPrimary)

                    Spacer()

                    Text(AlarmSound.sound(named: defaultSound)?.displayName ?? defaultSound)
                        .font(AppFont.body(14))
                        .foregroundStyle(.textSecondary)

                    Image(systemName: "chevron.forward")
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
                settingsRow {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .font(AppFont.body(14))
                        .foregroundStyle(.textSecondary)
                }

                settingsRow {
                    Button {
                        showingAbout = true
                    } label: {
                        HStack {
                            Text("About Shabbat Clock")
                            Spacer()
                            Image(systemName: "chevron.forward")
                                .font(.system(size: 14))
                                .foregroundStyle(.textSecondary)
                        }
                    }
                }

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
                    .stroke(Color.surfaceBorder, lineWidth: 0.5)
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
        .background(Color.surfaceCard)
    }

}

// MARK: - Section Header

struct SectionHeader: View {
    let title: LocalizedStringKey
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
                    .fill(Color.textSecondary.opacity(0.4))
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
                    Text("Built with ❤️")
                        .font(AppFont.caption(13))
                        .foregroundStyle(.textSecondary)

                    Text("© \(currentYear) Shabbat Clock")
                        .font(AppFont.caption(12))
                        .foregroundStyle(.textSecondary.opacity(0.6))
                }
                .padding(.bottom, 40)
            }
        }
        .presentationDetents([.medium])
    }

    private var currentYear: String {
        String(Calendar.current.component(.year, from: Date()))
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
}

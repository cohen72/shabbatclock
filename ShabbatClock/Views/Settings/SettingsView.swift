import SwiftUI

/// App settings view.
struct SettingsView: View {
    @Environment(\.requestReview) private var requestReview
    @AppStorage("isPremium") private var isPremium = false
    @AppStorage("defaultSound") private var defaultSound = "Lecha Dodi"
    @AppStorage("appearanceMode") private var appearanceMode: String = AppearanceMode.system.rawValue
    @AppStorage("appLanguage") private var appLanguage: String = AppLanguage.system.rawValue
    @AppStorage("shabbatReminderEnabled") private var shabbatReminderEnabled = true
    @AppStorage("shabbatReminderMinutesBefore") private var shabbatReminderMinutesBefore = 120

    @Environment(AlarmKitService.self) private var alarmService
    @StateObject private var locationManager = LocationManager.shared
    @State private var showingPremium = false
    @State private var showingAbout = false
    @State private var showingCitySearch = false
    #if DEBUG
    @State private var showingDebug = false
    #endif

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient.nightSky
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Premium section (top for visibility)
                        premiumSection

                        // Alarm permission warning (only in fallback mode)
                        if alarmService.isFallbackMode && alarmService.hasBeenAskedForAuthorization {
                            alarmPermissionSection
                        }

                        // Pre-Shabbat reminder settings
                        shabbatReminderSection

                        // Location section
                        locationSection

                        // Appearance section
                        appearanceSection

                        // Language section
                        languageSection

                        // Defaults section
                        defaultsSection

                        // About section
                        aboutSection
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
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
            #if DEBUG
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingDebug = true
                    } label: {
                        Image(systemName: "ladybug.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.goldAccent)
                    }
                }
            }
            .sheet(isPresented: $showingDebug) {
                NavigationStack {
                    DebugView()
                        .applyLanguageOverride(AppLanguage.current)
                }
            }
            #endif
        }
    }

    // MARK: - Alarm Permission Section

    private var alarmPermissionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Alarms", icon: "alarm.fill")

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.goldAccent)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Limited Alarm Mode")
                            .font(AppFont.body())
                            .foregroundStyle(.textPrimary)

                        Text("Allow in Settings for full alarm features")
                            .font(AppFont.caption(12))
                            .foregroundStyle(.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 14))
                        .foregroundStyle(.goldAccent)
                }
                .padding(16)
                .settingsCard()
            }
        }
    }

    // MARK: - Shabbat Reminder Section

    /// 0 = Off, positive values = minutes before candle lighting
    private let reminderOptions: [(String, Int)] = [
        ("Off", 0),
        ("30 min", 30),
        ("1 hour", 60),
        ("2 hours", 120),
        ("3 hours", 180),
    ]

    /// Combined value: 0 means off, >0 means enabled at that interval
    private var reminderSelection: Int {
        shabbatReminderEnabled ? (shabbatReminderMinutesBefore > 0 ? shabbatReminderMinutesBefore : 120) : 0
    }

    private var shabbatReminderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Shabbat", icon: "flame.fill")

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Pre-Shabbat Reminder")
                        .font(.system(size: 15))
                        .foregroundStyle(.textPrimary)

                    Text("Review alarms and keep the app running")
                        .font(.system(size: 11))
                        .foregroundStyle(.textSecondary)
                }

                Spacer()

                Picker("", selection: Binding(
                    get: { reminderSelection },
                    set: { newValue in
                        if newValue == 0 {
                            shabbatReminderEnabled = false
                        } else {
                            shabbatReminderEnabled = true
                            shabbatReminderMinutesBefore = newValue
                        }
                    }
                )) {
                    ForEach(reminderOptions, id: \.1) { option in
                        Text(option.0).tag(option.1)
                    }
                }
                .tint(.goldAccent)
            }
            .padding(16)
            .settingsCard()
        }
        .onChange(of: shabbatReminderEnabled) { _, _ in
            ShabbatReminderService.shared.reschedule()
        }
        .onChange(of: shabbatReminderMinutesBefore) { _, _ in
            ShabbatReminderService.shared.reschedule()
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

            Picker("Theme", selection: $appearanceMode) {
                Text("System").tag(AppearanceMode.system.rawValue)
                Text("Light").tag(AppearanceMode.light.rawValue)
                Text("Dark").tag(AppearanceMode.dark.rawValue)
            }
            .pickerStyle(.segmented)
            .padding(16)
            .settingsCard()
        }
    }

    // MARK: - Language Section

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Language", icon: "globe")

            Picker("Language", selection: $appLanguage) {
                Text("System").tag(AppLanguage.system.rawValue)
                Text(verbatim: "English").tag(AppLanguage.english.rawValue)
                Text(verbatim: "עברית").tag(AppLanguage.hebrew.rawValue)
            }
            .pickerStyle(.segmented)
            .padding(16)
            .settingsCard()
        }
    }

    // MARK: - Premium Section

    private var premiumSection: some View {
        Group {
            if isPremium {
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.goldAccent)

                        VStack(alignment: .leading, spacing: 2) {
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

                    Divider().overlay(Color.surfaceBorder)

                    // Manage subscription link
                    Button {
                        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack {
                            Text("Manage Subscription")
                                .font(AppFont.caption(13))
                                .foregroundStyle(.textSecondary)
                            Spacer()
                            Image(systemName: "arrow.up.forward")
                                .font(.system(size: 11))
                                .foregroundStyle(.textSecondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
                .settingsCard()
            } else {
                Button {
                    showingPremium = true
                } label: {
                    VStack(spacing: 0) {
                        // Gradient banner
                        HStack(spacing: 10) {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.white)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Upgrade to Premium")
                                    .font(AppFont.body(16))
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.white)

                                Text("Unlimited alarms • All sounds")
                                    .font(AppFont.caption(12))
                                    .foregroundStyle(.white.opacity(0.85))
                            }

                            Spacer()

                            Image(systemName: "chevron.forward")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color.goldAccent,
                                    Color.goldAccent.opacity(0.8),
                                    Color.accentPurple
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: .goldAccent.opacity(0.3), radius: 8, y: 4)
                }
            }
        }
    }

    // MARK: - Defaults Section

    private var defaultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Defaults", icon: "slider.horizontal.3")

            VStack(spacing: 8) {
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

                NavigationLink {
                    CustomSoundsSettingsView()
                } label: {
                    HStack {
                        Text("Custom Sounds")
                            .font(AppFont.body())
                            .foregroundStyle(.textPrimary)

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
                    Link(destination: AppURLs.supportMailto) {
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
                    Link(destination: AppURLs.support) {
                        HStack {
                            Text("Help & FAQ")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 14))
                                .foregroundStyle(.textSecondary)
                        }
                    }
                }

                settingsRow {
                    Link(destination: AppURLs.privacyPolicy) {
                        HStack {
                            Text("Privacy Policy")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 14))
                                .foregroundStyle(.textSecondary)
                        }
                    }
                }

                settingsRow {
                    Link(destination: AppURLs.termsOfUse) {
                        HStack {
                            Text("Terms of Use")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
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

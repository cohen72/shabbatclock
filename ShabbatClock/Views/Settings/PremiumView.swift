import SwiftUI
import StoreKit

/// Premium subscription paywall — beautiful, modern, conversion-optimized.
struct PremiumView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = StoreManager.shared

    @State private var selectedPlan: String = StoreManager.yearlyID
    @State private var isLoading = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var pulseAnimation = false

    private let features: [(icon: String, title: LocalizedStringKey, subtitle: LocalizedStringKey)] = [
        ("infinity", "Unlimited Alarms", "No limits on how many alarms you create"),
        ("music.note.list", "All Premium Sounds", "Unlock the full sound library"),
        ("mic.fill", "Record Your Own Sounds", "Create personalized alarm sounds"),
        ("timer", "Extended Durations", "Auto-stop up to 5 minutes"),
        ("heart.fill", "Support Development", "Help us keep improving Shabbat Clock"),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                LinearGradient.nightSky
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Top content
                    VStack(spacing: 14) {
                        heroSection
                        featuresSection
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)

                    Spacer(minLength: 12)

                    // Bottom-aligned: plans + subscribe + restore + fine print
                    VStack(spacing: 10) {
                        planSelectionSection
                        subscribeButton
                        finePrintSection
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) {
                        dismiss()
                    }
                }
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                pulseAnimation = true
            }
        }
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        VStack(spacing: 6) {
            // Animated crown icon
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.goldAccent.opacity(0.3), Color.clear],
                            center: .center,
                            startRadius: 12,
                            endRadius: 34
                        )
                    )
                    .frame(width: 64, height: 64)
                    .scaleEffect(pulseAnimation ? 1.1 : 0.9)

                Image(systemName: "crown.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.goldAccent, Color(hex: "E8B04A")],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }

            Text("Go Premium")
                .font(AppFont.header(24))
                .foregroundStyle(.textPrimary)

            Text("Unlock the full Shabbat Clock experience")
                .font(AppFont.body(14))
                .foregroundStyle(.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Features Section

    private var featuresSection: some View {
        VStack(spacing: 0) {
            ForEach(Array(features.enumerated()), id: \.offset) { index, feature in
                HStack(spacing: 12) {
                    Image(systemName: feature.icon)
                        .font(.system(size: 15))
                        .foregroundStyle(.goldAccent)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(Color.goldAccent.opacity(0.12))
                        )

                    VStack(alignment: .leading, spacing: 1) {
                        Text(feature.title)
                            .font(AppFont.body(14))
                            .fontWeight(.semibold)
                            .foregroundStyle(.textPrimary)

                        Text(feature.subtitle)
                            .font(AppFont.caption(11))
                            .foregroundStyle(.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.goldAccent)
                }
                .padding(.vertical, 8)

                if index < features.count - 1 {
                    Divider()
                        .overlay(Color.surfaceBorder)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.surfaceCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.surfaceBorder, lineWidth: 0.5)
                )
        )
    }

    // MARK: - Plan Selection

    private var planSelectionSection: some View {
        VStack(spacing: 8) {
            planCard(
                title: String(localized: "Yearly"),
                pricePerPeriod: store.yearlyProduct.map { $0.displayPrice + String(localized: "/year") }
                    ?? String(localized: "$14.99/year"),
                badge: savingsBadge ?? String(localized: "SAVE 71%"),
                isSelected: selectedPlan == StoreManager.yearlyID
            )
            .onTapGesture { selectedPlan = StoreManager.yearlyID }

            planCard(
                title: String(localized: "Weekly"),
                pricePerPeriod: store.weeklyProduct.map { $0.displayPrice + String(localized: "/week") }
                    ?? String(localized: "$0.99/week"),
                badge: nil,
                isSelected: selectedPlan == StoreManager.weeklyID
            )
            .onTapGesture { selectedPlan = StoreManager.weeklyID }
        }
    }

    private func planCard(
        title: String,
        pricePerPeriod: String,
        badge: String?,
        isSelected: Bool
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(isSelected ? Color.goldAccent : Color.surfaceBorder, lineWidth: 2)
                    .frame(width: 22, height: 22)

                if isSelected {
                    Circle()
                        .fill(Color.goldAccent)
                        .frame(width: 12, height: 12)
                }
            }

            HStack(spacing: 8) {
                Text(title)
                    .font(AppFont.body(15))
                    .fontWeight(.semibold)
                    .foregroundStyle(.textPrimary)

                if let badge {
                    Text(badge)
                        .font(AppFont.caption(9))
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.goldAccent, Color.accentPurple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                }
            }

            Spacer()

            Text(pricePerPeriod)
                .font(AppFont.body(15))
                .fontWeight(.semibold)
                .foregroundStyle(isSelected ? .goldAccent : .textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.surfaceCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            isSelected ? Color.goldAccent : Color.surfaceBorder,
                            lineWidth: isSelected ? 1.5 : 0.5
                        )
                )
        )
    }

    // MARK: - Subscribe Button

    private var subscribeButton: some View {
        VStack(spacing: 8) {
            Button {
                purchaseSelected()
            } label: {
                HStack(spacing: 8) {
                    if isLoading || store.isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Subscribe Now")
                            .font(AppFont.body(17))
                            .fontWeight(.bold)
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.goldAccent, Color.accentPurple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: .goldAccent.opacity(0.35), radius: 12, y: 6)
                )
            }
            .disabled(isLoading || store.isLoading || store.products.isEmpty)

            // Restore purchases
            Button {
                Task {
                    isLoading = true
                    await store.restorePurchases()
                    isLoading = false
                    if store.isPremium {
                        dismiss()
                    } else {
                        errorMessage = String(localized: "No previous purchases found")
                        showingError = true
                    }
                }
            } label: {
                Text("Restore Purchases")
                    .font(AppFont.body(14))
                    .foregroundStyle(.textSecondary)
            }
        }
    }

    // MARK: - Fine Print

    private var finePrintSection: some View {
        VStack(spacing: 4) {
            Text("Payment will be charged to your Apple ID account at confirmation of purchase. Subscription automatically renews unless canceled at least 24 hours before the end of the current period. You can manage and cancel your subscriptions in your App Store account settings.")
                .font(.system(size: 10))
                .foregroundStyle(.textSecondary.opacity(0.6))
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Link("Terms of Use", destination: AppURLs.termsOfUse)
                    .font(.system(size: 11))
                    .foregroundStyle(.textSecondary)
                Link("Privacy Policy", destination: AppURLs.privacyPolicy)
                    .font(.system(size: 11))
                    .foregroundStyle(.textSecondary)
            }
        }
    }

    // MARK: - Actions

    private func purchaseSelected() {
        guard let product = store.products.first(where: { $0.id == selectedPlan }) else { return }

        isLoading = true
        Task {
            do {
                let success = try await store.purchase(product)
                isLoading = false
                if success {
                    dismiss()
                }
            } catch {
                isLoading = false
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    // MARK: - Helpers

    private var savingsBadge: String? {
        let percent = store.yearlySavingsPercent
        guard percent > 0 else { return nil }
        return String(localized: "SAVE \(percent)%")
    }

}

// MARK: - Preview

#Preview {
    PremiumView()
}

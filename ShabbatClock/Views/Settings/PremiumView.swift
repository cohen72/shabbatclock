import SwiftUI
import StoreKit

/// Premium upgrade view.
struct PremiumView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("isPremium") private var isPremium = false

    @State private var isLoading = false
    @State private var showingError = false
    @State private var errorMessage = ""

    private let features = [
        ("infinity", "Unlimited Alarms", "Create as many alarms as you need"),
        ("music.note.list", "All 47 Sounds", "Access every alarm sound including Shabbat melodies"),
        ("slider.horizontal.3", "Custom Durations", "Set any auto-shutoff duration up to 10 minutes"),
        ("heart.fill", "Support Development", "Help us keep improving Shabbat Clock")
    ]

    var body: some View {
        ZStack {
            LinearGradient.nightSky
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.textSecondary)
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.1))
                            )
                    }

                    Spacer()
                }
                .padding()

                ScrollView {
                    VStack(spacing: 32) {
                        // Title section
                        VStack(spacing: 16) {
                            // Premium badge
                            HStack(spacing: 8) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 20))
                                Text("Premium")
                                    .font(AppFont.header(24))
                            }
                            .foregroundStyle(.goldAccent)

                            Text("Unlock the full\nShabbat Clock experience")
                                .font(AppFont.body(16))
                                .foregroundStyle(.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 20)

                        // Features
                        VStack(spacing: 16) {
                            ForEach(features, id: \.0) { feature in
                                FeatureRow(
                                    icon: feature.0,
                                    title: feature.1,
                                    description: feature.2
                                )
                            }
                        }
                        .padding(.horizontal, 24)

                        // Price card
                        VStack(spacing: 8) {
                            Text("One-time purchase")
                                .font(AppFont.caption(12))
                                .foregroundStyle(.textSecondary)

                            Text("$4.99")
                                .font(AppFont.timeDisplay(48))
                                .foregroundStyle(.textPrimary)

                            Text("Lifetime access • No subscription")
                                .font(AppFont.caption(13))
                                .foregroundStyle(.goldAccent)
                        }
                        .padding(.vertical, 24)
                        .frame(maxWidth: .infinity)
                        .glassMorphic(cornerRadius: 20, opacity: 0.15)
                        .padding(.horizontal, 24)

                        // Purchase button
                        Button {
                            purchase()
                        } label: {
                            HStack {
                                if isLoading {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("Upgrade Now")
                                        .font(AppFont.body(16))
                                        .fontWeight(.semibold)
                                }
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.accentPurple)
                                    .shadow(color: .accentPurple.opacity(0.4), radius: 10, y: 4)
                            )
                        }
                        .disabled(isLoading)
                        .padding(.horizontal, 24)

                        // Restore purchases
                        Button {
                            restorePurchases()
                        } label: {
                            Text("Restore Purchases")
                                .font(AppFont.body(14))
                                .foregroundStyle(.textSecondary)
                        }
                        .padding(.bottom, 40)
                    }
                }
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Actions

    private func purchase() {
        isLoading = true

        // Simulate purchase for now
        // In production, use StoreKit 2
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)

            await MainActor.run {
                isLoading = false
                isPremium = true
                dismiss()
            }
        }
    }

    private func restorePurchases() {
        isLoading = true

        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)

            await MainActor.run {
                isLoading = false
                // Check for existing purchases
                // For now, just show a message
                errorMessage = "No previous purchases found"
                showingError = true
            }
        }
    }
}

// MARK: - Feature Row

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.goldAccent)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(Color.goldAccent.opacity(0.15))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppFont.body())
                    .foregroundStyle(.textPrimary)

                Text(description)
                    .font(AppFont.caption(12))
                    .foregroundStyle(.textSecondary)
            }

            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    PremiumView()
}

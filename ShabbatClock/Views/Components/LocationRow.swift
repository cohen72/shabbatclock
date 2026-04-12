import SwiftUI

/// A tappable location row that requests permission or navigates to city search.
struct LocationRow: View {
    @ObservedObject var locationManager: LocationManager
    @State private var showingCitySearch = false
    @State private var showingLocationPrompt = false
    @State private var showingDeniedAlert = false

    var body: some View {
        Button {
            if locationManager.isAuthorized || locationManager.isUsingManualLocation {
                showingCitySearch = true
            } else if locationManager.authorizationStatus == .denied {
                showingDeniedAlert = true
            } else {
                showingLocationPrompt = true
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: locationManager.authorizationStatus == .denied
                      ? "location.slash.fill" : "location.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(locationManager.authorizationStatus == .denied
                                    ? .textSecondary : .accentPurple)

                if locationManager.locationName == "__unknown__" {
                    Text("Unknown Location")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.textPrimary)
                } else {
                    Text(locationManager.locationName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.textPrimary)
                }

                Image(systemName: "chevron.forward")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.surfaceSubtle)
                    .overlay(
                        Capsule()
                            .stroke(Color.surfaceBorder, lineWidth: 0.5)
                    )
            )
        }
        .sheet(isPresented: $showingCitySearch) {
            CitySearchView()
                .applyLanguageOverride(AppLanguage.current)
        }
        .fullScreenCover(isPresented: $showingLocationPrompt) {
            PermissionPromptView.location(
                onContinue: {
                    showingLocationPrompt = false
                    locationManager.requestPermission()
                },
                onSkip: {
                    showingLocationPrompt = false
                }
            )
        }
        .alert("Location Access Disabled", isPresented: $showingDeniedAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Choose City Manually") {
                showingCitySearch = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enable location in Settings for accurate prayer times, or choose your city manually.")
        }
    }
}

import SwiftUI

/// A tappable location row that requests permission or navigates to city search.
struct LocationRow: View {
    @ObservedObject var locationManager: LocationManager
    @State private var showingCitySearch = false

    var body: some View {
        Button {
            if locationManager.isAuthorized || locationManager.isUsingManualLocation {
                showingCitySearch = true
            } else {
                locationManager.requestPermission()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "location.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.accentPurple)

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
    }
}

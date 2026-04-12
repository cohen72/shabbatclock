import SwiftUI
import MapKit

/// Search and select a city for zmanim calculations.
struct CitySearchView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var locationManager = LocationManager.shared

    @State private var searchText = ""
    @State private var results: [MKMapItem] = []
    @State private var isSearching = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient.nightSky
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Search bar
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14))
                            .foregroundStyle(.textSecondary)

                        TextField("Search city...", text: $searchText)
                            .font(AppFont.body())
                            .foregroundStyle(.textPrimary)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                            .onSubmit { search() }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.surfaceCard)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.surfaceBorder, lineWidth: 0.5)
                            )
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                    // Use Current Location button
                    if locationManager.isAuthorized {
                        Button {
                            locationManager.clearManualLocation()
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.accentPurple)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Use Current Location")
                                        .font(AppFont.body())
                                        .foregroundStyle(.textPrimary)

                                    if locationManager.isUsingManualLocation {
                                        Text("Switch back to device location")
                                            .font(AppFont.caption(12))
                                            .foregroundStyle(.textSecondary)
                                    }
                                }

                                Spacer()

                                if !locationManager.isUsingManualLocation {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.accentPurple)
                                }
                            }
                            .padding(16)
                            .themeCard(cornerRadius: 14)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                    }

                    // Results
                    if isSearching {
                        Spacer()
                        ProgressView()
                            .tint(.accentPurple)
                        Spacer()
                    } else if !results.isEmpty {
                        ScrollView {
                            LazyVStack(spacing: 1) {
                                ForEach(results, id: \.self) { item in
                                    Button {
                                        selectCity(item)
                                    } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: "mappin.circle.fill")
                                                .font(.system(size: 20))
                                                .foregroundStyle(.goldAccent)

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(item.name ?? "Unknown")
                                                    .font(AppFont.body())
                                                    .foregroundStyle(.textPrimary)

                                                if let address = item.address {
                                                    Text(address.shortAddress ?? address.fullAddress)
                                                        .font(AppFont.caption(12))
                                                        .foregroundStyle(.textSecondary)
                                                        .lineLimit(1)
                                                }
                                            }

                                            Spacer()
                                        }
                                        .padding(16)
                                        .background(Color.surfaceSubtle)
                                    }
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            .padding(.bottom, 40)
                        }
                    } else {
                        Spacer()
                    }
                }
            }
            .navigationTitle("Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.textSecondary)
                    }
                }
            }
        }
        .onChange(of: searchText) { _, newValue in
            if newValue.count >= 2 {
                search()
            } else {
                results = []
            }
        }
    }

    private func search() {
        guard !searchText.isEmpty else { return }
        isSearching = true

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchText
        request.resultTypes = .address

        let search = MKLocalSearch(request: request)
        search.start { response, error in
            isSearching = false
            if let response {
                results = response.mapItems
            } else {
                results = []
            }
        }
    }

    private func selectCity(_ item: MKMapItem) {
        let coordinate = item.location.coordinate
        let location = CLLocation(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        let name: String
        if let address = item.address {
            name = address.shortAddress ?? address.fullAddress
        } else {
            name = item.name ?? "Selected Location"
        }
        locationManager.setManualLocation(location, name: name)
        ZmanimService.shared.calculateTodayZmanim()
        dismiss()
    }
}

#Preview {
    CitySearchView()
}

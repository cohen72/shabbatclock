import CoreLocation
import Combine
import MapKit

/// Manages location services for Zmanim calculations.
@MainActor
final class LocationManager: NSObject, ObservableObject {
    static let shared = LocationManager()

    @Published var location: CLLocation?
    @Published var locationName: String = "__unknown__"
    @Published var locationTimeZone: TimeZone = .current
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isLoading: Bool = false
    @Published var error: LocationError?
    @Published var isUsingManualLocation: Bool = false

    private let locationManager = CLLocationManager()

    enum LocationError: LocalizedError {
        case denied
        case restricted
        case unableToDetermine
        case geocodingFailed

        var errorDescription: String? {
            switch self {
            case .denied:
                return "Location access was denied. Please enable it in Settings."
            case .restricted:
                return "Location access is restricted on this device."
            case .unableToDetermine:
                return "Unable to determine your location."
            case .geocodingFailed:
                return "Unable to determine your city name."
            }
        }
    }

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        authorizationStatus = locationManager.authorizationStatus
        loadManualLocation()
    }

    // MARK: - Public Methods

    /// Request location permission.
    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    /// Request a single location update.
    func requestLocation() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            requestPermission()
            return
        }

        isLoading = true
        error = nil
        locationManager.requestLocation()
    }

    /// Get stored or default location.
    var currentOrDefaultLocation: CLLocation {
        location ?? CLLocation(latitude: 40.7128, longitude: -74.0060) // NYC default
    }

    /// Set a manual location override (from city search).
    func setManualLocation(_ newLocation: CLLocation, name: String) {
        location = newLocation
        locationName = name
        isUsingManualLocation = true
        error = nil

        UserDefaults.standard.set(newLocation.coordinate.latitude, forKey: "manualLatitude")
        UserDefaults.standard.set(newLocation.coordinate.longitude, forKey: "manualLongitude")
        UserDefaults.standard.set(name, forKey: "manualLocationName")
        UserDefaults.standard.set(true, forKey: "isUsingManualLocation")

        // Resolve timezone for the manual location
        reverseGeocodeForTimeZone(newLocation)
    }

    /// Resolve only the timezone for a location (used for manual locations where name is already known).
    private func reverseGeocodeForTimeZone(_ location: CLLocation) {
        Task {
            do {
                guard let request = MKReverseGeocodingRequest(location: location) else { return }
                let mapItems = try await request.mapItems
                if let tz = mapItems.first?.timeZone {
                    self.locationTimeZone = tz
                }
            } catch {
                print("[LocationManager] Timezone geocoding error: \(error)")
            }
        }
    }

    /// Clear the manual override and use device location.
    func clearManualLocation() {
        isUsingManualLocation = false
        UserDefaults.standard.removeObject(forKey: "manualLatitude")
        UserDefaults.standard.removeObject(forKey: "manualLongitude")
        UserDefaults.standard.removeObject(forKey: "manualLocationName")
        UserDefaults.standard.set(false, forKey: "isUsingManualLocation")
        requestLocation()
    }

    /// Whether location permission has been granted.
    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    // MARK: - Private Methods

    private func loadManualLocation() {
        guard UserDefaults.standard.bool(forKey: "isUsingManualLocation") else { return }
        let lat = UserDefaults.standard.double(forKey: "manualLatitude")
        let lon = UserDefaults.standard.double(forKey: "manualLongitude")
        guard lat != 0 || lon != 0 else { return }
        let loc = CLLocation(latitude: lat, longitude: lon)
        location = loc
        isUsingManualLocation = true
        // Re-geocode with current app locale to get localized name
        reverseGeocode(loc)
    }

    private func reverseGeocode(_ location: CLLocation) {
        Task {
            do {
                guard let request = MKReverseGeocodingRequest(location: location) else {
                    self.locationName = "__unknown__"
                    return
                }
                let mapItems = try await request.mapItems
                if let item = mapItems.first {
                    // Use item.address (iOS 26+) instead of addressRepresentations to avoid placemark deprecation
                    if let address = item.address {
                        self.locationName = address.shortAddress ?? address.fullAddress
                    } else if let name = item.name {
                        self.locationName = name
                    } else {
                        self.locationName = "__unknown__"
                    }
                    // Use the location's native timezone
                    if let tz = item.timeZone {
                        self.locationTimeZone = tz
                    }
                }
            } catch {
                print("[LocationManager] Geocoding error: \(error)")
                self.locationName = "__unknown__"
            }
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let location = locations.last else { return }

            self.location = location
            self.isLoading = false
            self.error = nil

            // Save to UserDefaults for offline use
            UserDefaults.standard.set(location.coordinate.latitude, forKey: "lastLatitude")
            UserDefaults.standard.set(location.coordinate.longitude, forKey: "lastLongitude")

            reverseGeocode(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.isLoading = false

            if let clError = error as? CLError {
                switch clError.code {
                case .denied:
                    self.error = .denied
                case .locationUnknown:
                    self.error = .unableToDetermine
                default:
                    self.error = .unableToDetermine
                }
            } else {
                self.error = .unableToDetermine
            }

            print("[LocationManager] Location error: \(error)")
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus

            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                requestLocation()
            case .denied:
                self.error = .denied
            case .restricted:
                self.error = .restricted
            case .notDetermined:
                break
            @unknown default:
                break
            }
        }
    }
}

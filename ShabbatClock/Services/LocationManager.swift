import CoreLocation
import Combine

/// Manages location services for Zmanim calculations.
@MainActor
final class LocationManager: NSObject, ObservableObject {
    static let shared = LocationManager()

    @Published var location: CLLocation?
    @Published var locationName: String = "Unknown Location"
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isLoading: Bool = false
    @Published var error: LocationError?

    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()

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

    // MARK: - Private Methods

    private func reverseGeocode(_ location: CLLocation) {
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            Task { @MainActor in
                if let error = error {
                    print("[LocationManager] Geocoding error: \(error)")
                    self?.locationName = "Unknown Location"
                    return
                }

                if let placemark = placemarks?.first {
                    let city = placemark.locality ?? placemark.administrativeArea ?? "Unknown"
                    let country = placemark.country ?? ""
                    self?.locationName = country.isEmpty ? city : "\(city), \(country)"
                }
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

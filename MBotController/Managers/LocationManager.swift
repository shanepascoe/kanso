import CoreLocation
import Combine

/// Wraps CLLocationManager and publishes GPS / location data.
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    @Published var latitude:           Double = 0
    @Published var longitude:          Double = 0
    @Published var altitude:           Double = 0   // metres above sea level
    @Published var speed:              Double = 0   // m/s (−1 if unavailable)
    @Published var course:             Double = 0   // degrees from true north
    @Published var horizontalAccuracy: Double = 0   // metres
    @Published var authStatus: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate          = self
        manager.desiredAccuracy   = kCLLocationAccuracyBestForNavigation
        manager.requestWhenInUseAuthorization()
    }

    func start()  { manager.startUpdatingLocation() }
    func stop()   { manager.stopUpdatingLocation() }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        latitude           = loc.coordinate.latitude
        longitude          = loc.coordinate.longitude
        altitude           = loc.altitude
        speed              = loc.speed
        course             = loc.course
        horizontalAccuracy = loc.horizontalAccuracy
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authStatus = manager.authorizationStatus
        if manager.authorizationStatus == .authorizedWhenInUse ||
           manager.authorizationStatus == .authorizedAlways {
            start()
        }
    }
}

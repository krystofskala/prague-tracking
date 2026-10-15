import CoreLocation
import Combine

/// Thin wrapper around CLLocationManager configured for continuous
/// foreground + background walking tracking. All location data stays
/// in-process — this class never performs any networking.
final class LocationTracker: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var isTracking = false

    /// Called on the main thread for each accepted location fix.
    var onLocation: ((CLLocation) -> Void)?

    private let manager = CLLocationManager()

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10
        manager.activityType = .fitness
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
    }

    /// Battery saving while standing still or riding (see PowerPolicy):
    /// updates keep flowing so tracking resumes by itself, just coarser.
    func setLowPower(_ lowPower: Bool) {
        manager.desiredAccuracy = lowPower ? kCLLocationAccuracyHundredMeters : kCLLocationAccuracyBest
        manager.distanceFilter = lowPower ? 50 : 10
    }

    func requestAuthorization() {
        manager.requestAlwaysAuthorization()
    }

    func startTracking() {
        isTracking = true
        manager.startUpdatingLocation()
    }

    func stopTracking() {
        isTracking = false
        manager.stopUpdatingLocation()
    }
}

extension LocationTracker: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations {
            // Reject fixes with no accuracy info or accuracy worse than 50m —
            // both are common right after waking from background and would
            // otherwise snap to the wrong street.
            guard location.horizontalAccuracy >= 0, location.horizontalAccuracy < 50 else { continue }
            onLocation?(location)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Transient failures (no fix yet, momentarily out of signal) are
        // expected and self-resolve on the next update; nothing to do here.
    }
}

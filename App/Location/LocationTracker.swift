import CoreLocation
import Combine

/// Continuous foreground + background walking tracking on iOS 17's
/// `CLLocationUpdate.liveUpdates`. Holding a `CLBackgroundActivitySession`
/// while tracking lets iOS relaunch the app in the background if it was
/// ended mid-walk; the classic `startUpdatingLocation` never did, so a
/// killed app stayed silent until opened by hand. Significant location
/// changes are a second way back in.
/// All location data stays in-process — this class never performs any
/// networking.
@MainActor
final class LocationTracker: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var isTracking = false

    /// Every fix, unfiltered; accuracy is up to the caller.
    var onLocation: ((CLLocation) -> Void)?
    /// Things worth a line in the event log (kind, detail).
    var onEvent: ((String, String) -> Void)?

    /// Used for the permission prompt and significant changes; fixes come
    /// from `liveUpdates`.
    private let manager = CLLocationManager()
    private var backgroundSession: CLBackgroundActivitySession?
    private var updatesTask: Task<Void, Never>?
    private var wasStationary = false

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    func requestAuthorization() {
        manager.requestAlwaysAuthorization()
    }

    func startTracking() {
        guard !isTracking else { return }
        isTracking = true
        backgroundSession = CLBackgroundActivitySession()
        manager.startMonitoringSignificantLocationChanges()
        updatesTask = Task { [weak self] in
            // The stream can end or throw (e.g. a location error); a silent
            // end looked like tracking while nothing was recorded, so start
            // it again after a short pause for as long as tracking is on.
            while !Task.isCancelled {
                do {
                    for try await update in CLLocationUpdate.liveUpdates(.fitness) {
                        guard let self, !Task.isCancelled else { return }
                        self.receive(update)
                    }
                    self?.onEvent?("chyba", "liveUpdates skončily, spouštím znovu")
                } catch {
                    self?.onEvent?("chyba", "liveUpdates: \(error.localizedDescription), spouštím znovu")
                }
                guard self?.isTracking == true else { return }
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    private func receive(_ update: CLLocationUpdate) {
        if update.isStationary != wasStationary {
            wasStationary = update.isStationary
            // iOS pauses GPS by itself while you stand still.
            onEvent?("gps", update.isStationary ? "stojí, iOS pozastavil GPS" : "pohyb, GPS běží")
        }
        if let location = update.location {
            onLocation?(location)
        }
    }

    func stopTracking() {
        isTracking = false
        updatesTask?.cancel()
        updatesTask = nil
        backgroundSession?.invalidate()
        backgroundSession = nil
        manager.stopMonitoringSignificantLocationChanges()
    }
}

extension LocationTracker: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            self.onEvent?("opravneni", Self.describe(status))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Significant changes are coarse (cell towers); they only matter as a
        // wake-up, the precise fixes come from liveUpdates.
        Task { @MainActor in
            self.onEvent?("vyznamna_zmena", "\(locations.count) bodů")
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Used to be swallowed silently; logged so gaps can be explained.
        let message = error.localizedDescription
        Task { @MainActor in
            self.onEvent?("chyba", message)
        }
    }

    private static func describe(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .authorizedAlways: return "vždy"
        case .authorizedWhenInUse: return "jen při používání"
        case .denied: return "zamítnuto"
        case .restricted: return "omezeno"
        case .notDetermined: return "nezvoleno"
        @unknown default: return "neznámé"
        }
    }
}

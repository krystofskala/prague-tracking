import Foundation

/// Decides when GPS can drop to a battery-saving mode while tracking.
/// Best-accuracy GPS is only useful while walking; standing still (a café,
/// sitting on a bench) or riding a tram doesn't record streets anyway.
/// Location updates keep running in low power, because iOS won't let a
/// background app restart them, so tracking resumes as soon as you walk.
///
/// Pure logic with injected time so it's testable without Core Motion.
public struct PowerPolicy: Sendable {
    public enum Activity: Sendable {
        case walking, stationary, vehicle, unknown
    }

    /// How long you have to stand still before saving power; short stops
    /// (traffic lights, a look at the map) keep full accuracy.
    public let stationaryDelay: TimeInterval
    private var stationarySince: Date?
    private var current: Activity = .unknown

    public init(stationaryDelay: TimeInterval = 2 * 60) {
        self.stationaryDelay = stationaryDelay
    }

    public mutating func update(_ activity: Activity, at time: Date) {
        // Low-confidence readings keep the last known state, so wobbling
        // confidence doesn't restart the stationary timer or wake full GPS.
        guard activity != .unknown else { return }
        if activity == .stationary, current != .stationary {
            // A tram or car stopping (stop, traffic) stays in low power
            // instead of waking full GPS at every stop.
            stationarySince = current == .vehicle ? time.addingTimeInterval(-stationaryDelay) : time
        }
        current = activity
    }

    public func isLowPower(at time: Date) -> Bool {
        switch current {
        case .walking, .unknown:
            return false
        case .vehicle:
            return true
        case .stationary:
            guard let since = stationarySince else { return false }
            return time.timeIntervalSince(since) >= stationaryDelay
        }
    }
}

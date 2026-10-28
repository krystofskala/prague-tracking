import Foundation

/// Decides when tracking can thin out fixes to save battery.
/// Every fix is useful while walking; standing still (a café, sitting on a
/// bench) or riding a tram doesn't record streets anyway.
/// GPS keeps running at full accuracy in every mode: dropping to coarse GPS
/// used to make the app throw away every fix, so it never noticed you had
/// started walking again (the gaps after a tram ride).
///
/// Pure logic with injected time so it's testable without Core Motion.
public struct PowerPolicy: Sendable {
    public enum Activity: Sendable {
        case walking, stationary, vehicle, unknown
    }

    /// Chosen by the user in the app.
    public enum Mode: String, Sendable, CaseIterable {
        /// Every fix all the time: best route, more battery.
        case precise
        /// Thin out fixes while riding or standing for a while.
        case saving
    }

    public var mode: Mode
    /// How long you have to stand still before saving power; short stops
    /// (traffic lights, a look at the map, getting off a tram) keep full
    /// accuracy.
    public let stationaryDelay: TimeInterval
    private var stationarySince: Date?
    private var current: Activity = .unknown

    public init(mode: Mode = .precise, stationaryDelay: TimeInterval = 2 * 60) {
        self.mode = mode
        self.stationaryDelay = stationaryDelay
    }

    public mutating func update(_ activity: Activity, at time: Date) {
        // Ambiguous readings keep the last known state, so wobbling
        // confidence doesn't restart the stationary timer.
        guard activity != .unknown else { return }
        if activity == .stationary, current != .stationary {
            // Also after a ride: stepping off a tram reads as "stationary"
            // first, and the walk that follows must not start thinned out.
            stationarySince = time
        }
        current = activity
    }

    public func isLowPower(at time: Date) -> Bool {
        guard mode == .saving else { return false }
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

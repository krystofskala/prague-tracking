import CoreMotion
import StreetTrackerCore

/// Filters out GPS fixes recorded while confidently in a car or on a bike,
/// so a bus or car ride doesn't get logged as "walked" streets. Defaults to
/// permissive (`isLikelyWalking == true`) when Core Motion data isn't
/// available or hasn't reported yet — under-filtering (occasionally
/// recording a non-walking fix) is a much smaller problem than silently
/// dropping real walking data because of a missing/denied permission.
final class WalkingActivityMonitor: ObservableObject {
    @Published private(set) var isLikelyWalking = true
    /// Coarse activity for the battery-saving policy.
    @Published private(set) var activity: PowerPolicy.Activity = .unknown

    private let activityManager = CMMotionActivityManager()

    var isAvailable: Bool {
        CMMotionActivityManager.isActivityAvailable()
    }

    func start() {
        guard isAvailable else { return }
        activityManager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let self, let activity else { return }
            self.isLikelyWalking = Self.shouldTrack(activity)
            self.activity = Self.classify(activity)
        }
    }

    func stop() {
        activityManager.stopActivityUpdates()
    }

    private static func classify(_ activity: CMMotionActivity) -> PowerPolicy.Activity {
        guard activity.confidence != .low else { return .unknown }
        if activity.automotive || activity.cycling { return .vehicle }
        if activity.walking || activity.running { return .walking }
        if activity.stationary { return .stationary }
        return .unknown
    }

    private static func shouldTrack(_ activity: CMMotionActivity) -> Bool {
        // Only reject on confident automotive/cycling readings; low-confidence
        // or ambiguous readings fall through to "keep tracking".
        if activity.automotive && activity.confidence != .low { return false }
        if activity.cycling && activity.confidence != .low { return false }
        return true
    }
}

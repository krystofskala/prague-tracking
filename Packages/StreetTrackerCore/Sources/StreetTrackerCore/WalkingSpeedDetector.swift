import Foundation

/// Notices walking from GPS speed alone. Core Motion often reports the end
/// of a tram or car ride minutes late while the app runs in the background,
/// and until then the start of the walk wasn't counted. A steady walking
/// pace for `requiredDuration` is enough to say "walking" without it.
/// While Core Motion still says "vehicle", a longer pace is required
/// (`vehicleDuration`), so a tram or car crawling in traffic doesn't count.
///
/// Pure logic with injected time so it's testable without Core Location.
public struct WalkingSpeedDetector: Sendable {
    /// m/s; slow strolls to a brisk walk. A tram or car crawling this slowly
    /// for the whole window is rare, and a street still needs two fixes.
    public static let walkingSpeeds: ClosedRange<Double> = 0.4...2.5

    public let requiredDuration: TimeInterval
    public let vehicleDuration: TimeInterval
    /// A fix with no speed this long ends the streak (GPS paused, tunnel).
    public let maxGap: TimeInterval
    private var walkingSince: Date?
    private var lastFix: Date?

    public init(requiredDuration: TimeInterval = 30, vehicleDuration: TimeInterval = 120, maxGap: TimeInterval = 20) {
        self.requiredDuration = requiredDuration
        self.vehicleDuration = vehicleDuration
        self.maxGap = maxGap
    }

    /// Feed every fix. `speed` is negative when the GPS doesn't know it;
    /// such fixes (common between tall buildings) neither break nor extend
    /// the streak.
    public mutating func observe(speed: Double, at time: Date) {
        guard speed >= 0 else { return }
        defer { lastFix = time }
        guard Self.walkingSpeeds.contains(speed) else {
            walkingSince = nil
            return
        }
        if let lastFix, time.timeIntervalSince(lastFix) > maxGap {
            walkingSince = nil
        }
        if walkingSince == nil {
            walkingSince = time
        }
    }

    public func isWalking(at time: Date, inVehicle: Bool = false) -> Bool {
        guard let walkingSince, let lastFix, time.timeIntervalSince(lastFix) <= maxGap else { return false }
        return lastFix.timeIntervalSince(walkingSince) >= (inVehicle ? vehicleDuration : requiredDuration)
    }
}

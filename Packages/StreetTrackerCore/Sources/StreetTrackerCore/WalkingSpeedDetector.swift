import Foundation

/// Notices walking from GPS speed alone. Core Motion often reports the end
/// of a tram or car ride minutes late while the app runs in the background,
/// and until then the start of the walk wasn't counted. A steady walking
/// pace for `requiredDuration` is enough to say "walking" without it.
///
/// Pure logic with injected time so it's testable without Core Location.
public struct WalkingSpeedDetector: Sendable {
    /// m/s; slow strolls to a brisk walk. A tram or car crawling this slowly
    /// for the whole window is rare, and a street still needs two fixes.
    public static let walkingSpeeds: ClosedRange<Double> = 0.4...2.5

    public let requiredDuration: TimeInterval
    /// A fix with no speed this long ends the streak (GPS paused, tunnel).
    public let maxGap: TimeInterval
    private var walkingSince: Date?
    private var lastFix: Date?

    public init(requiredDuration: TimeInterval = 30, maxGap: TimeInterval = 20) {
        self.requiredDuration = requiredDuration
        self.maxGap = maxGap
    }

    /// Feed every fix. `speed` is negative when the GPS doesn't know it.
    public mutating func observe(speed: Double, at time: Date) {
        defer { lastFix = time }
        guard speed >= 0, Self.walkingSpeeds.contains(speed) else {
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

    public func isWalking(at time: Date) -> Bool {
        guard let walkingSince, let lastFix, time.timeIntervalSince(lastFix) <= maxGap else { return false }
        return lastFix.timeIntervalSince(walkingSince) >= requiredDuration
    }
}

import XCTest
@testable import StreetTrackerCore

final class WalkingSpeedDetectorTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testSteadyWalkingPaceCountsAfterWindow() {
        var detector = WalkingSpeedDetector()
        for s in stride(from: 0, through: 20, by: 5) {
            detector.observe(speed: 1.3, at: t0.addingTimeInterval(Double(s)))
        }
        XCTAssertFalse(detector.isWalking(at: t0.addingTimeInterval(20)))
        for s in stride(from: 25, through: 35, by: 5) {
            detector.observe(speed: 1.3, at: t0.addingTimeInterval(Double(s)))
        }
        XCTAssertTrue(detector.isWalking(at: t0.addingTimeInterval(35)))
    }

    func testVehicleSpeedResetsStreak() {
        var detector = WalkingSpeedDetector()
        for s in stride(from: 0, through: 40, by: 5) {
            detector.observe(speed: s == 20 ? 8 : 1.3, at: t0.addingTimeInterval(Double(s)))
        }
        XCTAssertFalse(detector.isWalking(at: t0.addingTimeInterval(40)))
    }

    func testUnknownSpeedResetsStreak() {
        var detector = WalkingSpeedDetector()
        detector.observe(speed: 1.3, at: t0)
        detector.observe(speed: -1, at: t0.addingTimeInterval(20))
        detector.observe(speed: 1.3, at: t0.addingTimeInterval(25))
        detector.observe(speed: 1.3, at: t0.addingTimeInterval(40))
        XCTAssertFalse(detector.isWalking(at: t0.addingTimeInterval(40)))
    }

    func testLongGapEndsWalking() {
        var detector = WalkingSpeedDetector()
        for s in stride(from: 0, through: 40, by: 5) {
            detector.observe(speed: 1.3, at: t0.addingTimeInterval(Double(s)))
        }
        XCTAssertTrue(detector.isWalking(at: t0.addingTimeInterval(45)))
        XCTAssertFalse(detector.isWalking(at: t0.addingTimeInterval(120)))
        detector.observe(speed: 1.3, at: t0.addingTimeInterval(120))
        XCTAssertFalse(detector.isWalking(at: t0.addingTimeInterval(120)))
    }
}

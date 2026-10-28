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

    func testUnknownSpeedDoesNotBreakStreak() {
        // Between tall buildings every few fixes come without speed.
        var detector = WalkingSpeedDetector()
        for s in stride(from: 0, through: 40, by: 5) {
            detector.observe(speed: s % 25 == 0 && s > 0 ? -1 : 1.3, at: t0.addingTimeInterval(Double(s)))
        }
        XCTAssertTrue(detector.isWalking(at: t0.addingTimeInterval(40)))
    }

    func testCrawlingInTrafficIsNotWalkingWhileInVehicle() {
        var detector = WalkingSpeedDetector()
        for s in stride(from: 0, through: 60, by: 5) {
            detector.observe(speed: 1.5, at: t0.addingTimeInterval(Double(s)))
        }
        XCTAssertFalse(detector.isWalking(at: t0.addingTimeInterval(60), inVehicle: true))
        XCTAssertTrue(detector.isWalking(at: t0.addingTimeInterval(60), inVehicle: false))
        for s in stride(from: 65, through: 120, by: 5) {
            detector.observe(speed: 1.5, at: t0.addingTimeInterval(Double(s)))
        }
        // A real walk after a ride Core Motion hasn't noticed yet.
        XCTAssertTrue(detector.isWalking(at: t0.addingTimeInterval(120), inVehicle: true))
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

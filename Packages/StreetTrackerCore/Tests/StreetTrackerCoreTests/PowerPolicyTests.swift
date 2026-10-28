import XCTest
@testable import StreetTrackerCore

final class PowerPolicyTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testFullAccuracyWhileWalkingOrUnknown() {
        var policy = PowerPolicy(mode: .saving)
        XCTAssertFalse(policy.isLowPower(at: t0))
        policy.update(.walking, at: t0)
        XCTAssertFalse(policy.isLowPower(at: t0.addingTimeInterval(3600)))
    }

    func testShortStopKeepsFullAccuracy() {
        var policy = PowerPolicy(mode: .saving)
        policy.update(.stationary, at: t0)
        XCTAssertFalse(policy.isLowPower(at: t0.addingTimeInterval(60)))
    }

    func testLongStopSavesPowerAndWalkingRestoresIt() {
        var policy = PowerPolicy(mode: .saving)
        policy.update(.stationary, at: t0)
        policy.update(.stationary, at: t0.addingTimeInterval(90)) // repeated readings don't reset the timer
        XCTAssertTrue(policy.isLowPower(at: t0.addingTimeInterval(121)))
        policy.update(.walking, at: t0.addingTimeInterval(300))
        XCTAssertFalse(policy.isLowPower(at: t0.addingTimeInterval(300)))
    }

    func testVehicleSavesPowerImmediately() {
        var policy = PowerPolicy(mode: .saving)
        policy.update(.vehicle, at: t0)
        XCTAssertTrue(policy.isLowPower(at: t0))
    }

    func testGettingOffATramKeepsFullAccuracy() {
        var policy = PowerPolicy(mode: .saving)
        policy.update(.vehicle, at: t0)
        policy.update(.stationary, at: t0.addingTimeInterval(60)) // stepped off, Core Motion not yet "walking"
        XCTAssertFalse(policy.isLowPower(at: t0.addingTimeInterval(61)))
        XCTAssertTrue(policy.isLowPower(at: t0.addingTimeInterval(181)))
    }

    func testLowConfidenceReadingsDoNotRestartStationaryTimer() {
        var policy = PowerPolicy(mode: .saving)
        policy.update(.stationary, at: t0)
        policy.update(.unknown, at: t0.addingTimeInterval(60))
        policy.update(.stationary, at: t0.addingTimeInterval(90))
        XCTAssertTrue(policy.isLowPower(at: t0.addingTimeInterval(121)))
    }

    func testPreciseModeNeverSavesPower() {
        var policy = PowerPolicy(mode: .precise)
        policy.update(.vehicle, at: t0)
        XCTAssertFalse(policy.isLowPower(at: t0))
        policy.update(.stationary, at: t0.addingTimeInterval(10))
        XCTAssertFalse(policy.isLowPower(at: t0.addingTimeInterval(3600)))
    }
}

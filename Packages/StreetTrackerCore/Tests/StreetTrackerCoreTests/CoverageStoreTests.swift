import XCTest
@testable import StreetTrackerCore

final class CoverageStoreTests: XCTestCase {
    private func makeGraph() -> StreetGraph {
        let s1 = StreetSegment(id: "1", name: "A", points: [
            Coordinate(latitude: 50.08, longitude: 14.40),
            Coordinate(latitude: 50.081, longitude: 14.40)
        ], lengthMeters: 100, district: "Malá Strana")
        let s2 = StreetSegment(id: "2", name: "B", points: [
            Coordinate(latitude: 50.08, longitude: 14.41),
            Coordinate(latitude: 50.081, longitude: 14.41)
        ], lengthMeters: 300, district: "Malá Strana")
        let s3 = StreetSegment(id: "3", name: "C", points: [
            Coordinate(latitude: 50.09, longitude: 14.42),
            Coordinate(latitude: 50.091, longitude: 14.42)
        ], lengthMeters: 200, district: "Vinohrady")
        return StreetGraph(segments: ["1": s1, "2": s2, "3": s3])
    }

    func testCoverageFractionIsZeroInitially() {
        let store = CoverageStore()
        XCTAssertEqual(store.coverageFraction(graph: makeGraph()), 0)
    }

    func testCoverageFractionWeightsByLength() {
        let store = CoverageStore()
        store.recordPass(segmentID: "1") // 100m of 600m total
        XCTAssertEqual(store.coverageFraction(graph: makeGraph()), 100.0 / 600.0, accuracy: 0.0001)
    }

    func testRecordPassIncrementsCount() {
        let store = CoverageStore()
        store.recordPass(segmentID: "1")
        store.recordPass(segmentID: "1")
        XCTAssertEqual(store.passCount(for: "1"), 2)
        XCTAssertEqual(store.passCount(for: "unknown"), 0)
    }

    func testDistrictCoverageIsPerDistrict() {
        let store = CoverageStore()
        store.recordPass(segmentID: "1") // Malá Strana: 100 of 400
        let coverage = store.districtCoverage(graph: makeGraph())
        XCTAssertEqual(coverage["Malá Strana"] ?? -1, 100.0 / 400.0, accuracy: 0.0001)
        XCTAssertEqual(coverage["Vinohrady"] ?? -1, 0, accuracy: 0.0001)
    }

    // MARK: - Passes from GPS fixes

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testWalkingAlongOneStreetIsOnePass() {
        let store = CoverageStore()
        for i in 0..<30 { // one fix every ~10 m along a 300 m street
            store.recordFix(on: "2", at: t0.addingTimeInterval(Double(i) * 8))
        }
        XCTAssertEqual(store.passCount(for: "2"), 1)
    }

    func testSingleFixOnCrossStreetDoesNotCount() {
        let store = CoverageStore()
        store.recordFix(on: "1", at: t0)
        store.recordFix(on: "1", at: t0.addingTimeInterval(8))
        store.recordFix(on: "3", at: t0.addingTimeInterval(16)) // snapped to the cross street once
        store.recordFix(on: "1", at: t0.addingTimeInterval(24))
        store.recordFix(on: "1", at: t0.addingTimeInterval(32))
        XCTAssertEqual(store.passCount(for: "3"), 0)
        XCTAssertEqual(store.passCount(for: "1"), 1, "back on the same street within minutes = same pass")
    }

    func testComingBackLaterIsANewPass() {
        let store = CoverageStore()
        store.recordFix(on: "1", at: t0)
        XCTAssertTrue(store.recordFix(on: "1", at: t0.addingTimeInterval(8)))
        store.recordFix(on: "2", at: t0.addingTimeInterval(60))
        store.recordFix(on: "2", at: t0.addingTimeInterval(68))
        store.recordFix(on: "1", at: t0.addingTimeInterval(20 * 60))
        XCTAssertTrue(store.recordFix(on: "1", at: t0.addingTimeInterval(20 * 60 + 8)))
        XCTAssertEqual(store.passCount(for: "1"), 2)
    }

    func testLongWalkOnOneStreetStaysOnePass() {
        // Refreshing on every fix: a 25-minute walk along one long street
        // must not tick over into a second pass after rewalkInterval.
        let store = CoverageStore()
        for i in 0..<200 {
            store.recordFix(on: "2", at: t0.addingTimeInterval(Double(i) * 8))
        }
        XCTAssertEqual(store.passCount(for: "2"), 1)
    }

    func testNoiseAlternatingBetweenTwoCloseSegmentsCountsBoth() {
        // Sidewalk and road a few metres apart: GPS flips A, B, A, B...
        let store = CoverageStore()
        for i in 0..<6 {
            store.recordFix(on: i.isMultiple(of: 2) ? "1" : "2", at: t0.addingTimeInterval(Double(i) * 8))
        }
        XCTAssertEqual(store.passCount(for: "1"), 1)
        XCTAssertEqual(store.passCount(for: "2"), 1)
    }

    func testShortPassageCountsOnSingleFix() {
        let store = CoverageStore()
        XCTAssertTrue(store.recordFix(on: "1", at: t0, segmentLengthMeters: 12))
        XCTAssertFalse(store.recordFix(on: "2", at: t0.addingTimeInterval(8), segmentLengthMeters: 300))
    }

    func testFixBeforeARideDoesNotConfirmFixAfterIt() {
        // Fixes during a tram ride are dropped before reaching the store;
        // the last walking fix is minutes old by the time you get off.
        let store = CoverageStore()
        store.recordFix(on: "1", at: t0)
        XCTAssertFalse(store.recordFix(on: "1", at: t0.addingTimeInterval(5 * 60)))
        XCTAssertEqual(store.passCount(for: "1"), 0)
    }

    // MARK: - CoverageSummary

    func testSummaryMatchesFullRecomputation() {
        let graph = makeGraph()
        let store = CoverageStore(passCounts: ["1": 3])
        var summary = CoverageSummary(graph: graph, passCounts: store.passCounts)
        XCTAssertEqual(summary.fraction, store.coverageFraction(graph: graph), accuracy: 1e-9)

        store.recordPass(segmentID: "3")
        summary.markWalked("3")
        summary.markWalked("3") // repeated passes don't double count
        summary.markWalked("unknown-id")
        XCTAssertEqual(summary.fraction, store.coverageFraction(graph: graph), accuracy: 1e-9)
        XCTAssertEqual(summary.districtFractions, store.districtCoverage(graph: graph))
    }
}

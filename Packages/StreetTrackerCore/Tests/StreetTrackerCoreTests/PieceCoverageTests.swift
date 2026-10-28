import XCTest
@testable import StreetTrackerCore

final class PieceCoverageTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let north = Coordinate(latitude: 50.0, longitude: 14.4)

    /// One straight street 50.0 → 50.003 north (~334 m, 17 pieces).
    private func graph() -> StreetGraph {
        let points = [north, Coordinate(latitude: 50.003, longitude: 14.4)]
        return StreetGraph(segments: [
            "long": StreetSegment(id: "long", name: "Dlouhá", points: points, lengthMeters: Geo.polylineLength(points), district: "Praha 1"),
        ])
    }

    private func fixes(_ range: ClosedRange<Int>, every seconds: Double = 10) -> [Fix] {
        range.map { i in
            Fix(time: t0.addingTimeInterval(Double(i) * seconds), coordinate: Coordinate(latitude: 50.0 + Double(i) * 0.0001, longitude: 14.4))
        }
    }

    func testMatchKnowsWhereAlongTheStreet() {
        let g = graph()
        let match = MapMatcher(graph: g).match(Coordinate(latitude: 50.001, longitude: 14.40005))!
        XCTAssertEqual(match.alongMeters, 111.2, accuracy: 1)
    }

    func testOnlyTheWalkedPartCounts() {
        let g = graph()
        let result = CoverageRebuild.rebuild(fixes: fixes(0...9), graph: g, matcher: MapMatcher(graph: g))
        XCTAssertEqual(result.passCounts["long"], 1)
        let walked = CoverageRebuild.walkedMeters(passCounts: result.passCounts, pieces: result.pieces, graph: g)["long"]!
        XCTAssertEqual(walked, 100, accuracy: 25)
        let street = StreetProgress.streets(graph: g, walkedMeters: [ "long": walked ])[0]
        XCTAssertFalse(street.isDone())
        // Before pieces, the whole street counted.
        XCTAssertTrue(StreetProgress.streets(graph: g, passCounts: result.passCounts)[0].isDone())
    }

    func testFixesFarApartInTimeDontFillTheStreet() {
        let g = graph()
        let segment = g.segments["long"]!
        let matcher = MapMatcher(graph: g)
        var pieces = PieceCoverage()
        var tracker = PieceTracker()
        let a = matcher.match(north)!
        let b = matcher.match(Coordinate(latitude: 50.0025, longitude: 14.4))!
        XCTAssertTrue(tracker.record(a, at: t0, graph: g, into: &pieces))
        _ = tracker.record(b, at: t0.addingTimeInterval(600), graph: g, into: &pieces)
        XCTAssertEqual(pieces.walked["long"]?.count, 2)
        // Walking pace: 89 m in 55 s fills everything between (pieces 0–4).
        let c = matcher.match(Coordinate(latitude: 50.0008, longitude: 14.4))!
        var filled = PieceCoverage()
        var walker = PieceTracker()
        _ = walker.record(a, at: t0, graph: g, into: &filled)
        _ = walker.record(c, at: t0.addingTimeInterval(55), graph: g, into: &filled)
        XCTAssertEqual(filled.fraction(of: segment), 5.0 / 17.0, accuracy: 0.01)
        // The same 280 m in 55 s is too fast for walking: no fill.
        var fast = PieceCoverage()
        var rider = PieceTracker()
        _ = rider.record(a, at: t0, graph: g, into: &fast)
        _ = rider.record(b, at: t0.addingTimeInterval(55), graph: g, into: &fast)
        XCTAssertEqual(fast.walked["long"]?.count, 2)
    }

    func testHandMarkedAndPreLogStreetsCountWhole() {
        let g = graph()
        let manual = CoverageRebuild.rebuild(fixes: fixes(0...3), manualSegments: ["long"], graph: g, matcher: MapMatcher(graph: g))
        XCTAssertEqual(CoverageRebuild.walkedMeters(passCounts: manual.passCounts, pieces: manual.pieces, graph: g)["long"]!,
                       g.segments["long"]!.lengthMeters, accuracy: 0.01)
        let legacy = CoverageRebuild.rebuild(fixes: [], legacy: ["long": 1], graph: g, matcher: MapMatcher(graph: g))
        XCTAssertTrue(legacy.pieces.whole.contains("long"))
        // Passes with no pieces at all (recorded before E4) count whole too.
        XCTAssertEqual(CoverageRebuild.walkedMeters(passCounts: ["long": 1], pieces: PieceCoverage(), graph: g)["long"]!,
                       g.segments["long"]!.lengthMeters, accuracy: 0.01)
        // A crossing (pieces, no confirmed pass) doesn't count.
        var crossing = PieceCoverage()
        crossing.mark(g.segments["long"]!, from: 0, to: 5)
        XCTAssertNil(CoverageRebuild.walkedMeters(passCounts: [:], pieces: crossing, graph: g)["long"])
    }

    func testWalkedLinesAreTheWalkedRuns() {
        let g = graph()
        let segment = g.segments["long"]!
        var pieces = PieceCoverage()
        pieces.mark(segment, from: 0, to: 30)
        pieces.mark(segment, from: 200, to: 210)
        let lines = pieces.walkedLines(of: segment)!
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(Geo.polylineLength(lines[0]), 2 * segment.lengthMeters / 17, accuracy: 1)
        pieces.markWhole("long")
        XCTAssertNil(pieces.walkedLines(of: segment))
    }

    func testSummaryWithWalkedMeters() {
        let g = graph()
        var summary = CoverageSummary(graph: g, walkedMeters: ["long": 100])
        XCTAssertEqual(summary.fraction, 100 / g.totalLengthMeters, accuracy: 1e-9)
        summary.setWalked("long", meters: 150)
        XCTAssertEqual(summary.walkedLengthMeters, 150, accuracy: 1e-9)
        XCTAssertEqual(summary.districtFractions["Praha 1"]!, 150 / g.totalLengthMeters, accuracy: 1e-9)
    }

    func testPiecesSurviveJSON() throws {
        var pieces = PieceCoverage()
        pieces.mark(graph().segments["long"]!, from: 0, to: 50)
        pieces.markWhole("other")
        let decoded = try JSONDecoder().decode(PieceCoverage.self, from: JSONEncoder().encode(pieces))
        XCTAssertEqual(decoded, pieces)
    }
}

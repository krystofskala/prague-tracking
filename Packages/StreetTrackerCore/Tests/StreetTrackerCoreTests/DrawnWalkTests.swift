import XCTest
@testable import StreetTrackerCore

final class DrawnWalkTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let a = Coordinate(latitude: 50.0, longitude: 14.4)
    private let b = Coordinate(latitude: 50.003, longitude: 14.4)

    func testStrokeBecomesAWalkAtWalkingPace() {
        let fixes = DrawnWalk.fixes(strokes: [[a, b]], start: start)
        XCTAssertEqual(fixes.first?.time, start)
        XCTAssertTrue(fixes.allSatisfy { $0.walking && $0.accuracy == 5 })
        let length = Geo.distance(a, b)
        XCTAssertEqual(fixes.last!.time.timeIntervalSince(start), length / DrawnWalk.speed, accuracy: 1)
        for (x, y) in zip(fixes, fixes.dropFirst()) {
            XCTAssertLessThanOrEqual(Geo.distance(x.coordinate, y.coordinate), DrawnWalk.step + 0.01)
        }
        let walks = WalkSplitter.walks(from: fixes)
        XCTAssertEqual(walks.count, 1, "333 m drawn is one walk")
    }

    func testSecondStrokeContinuesInTimeAndShortStrokesAreSkipped() {
        let c = Coordinate(latitude: 50.003, longitude: 14.401)
        let d = Coordinate(latitude: 50.0, longitude: 14.401)
        let fixes = DrawnWalk.fixes(strokes: [[a, b], [c], [c, d]], start: start)
        XCTAssertEqual(fixes.filter { $0.coordinate == c }.count, 1)
        XCTAssertEqual(fixes.map(\.time), fixes.map(\.time).sorted())
        let gap = fixes.first { $0.coordinate == c }!.time.timeIntervalSince(fixes.last { $0.coordinate == b }!.time)
        XCTAssertEqual(gap, Geo.distance(b, c) / DrawnWalk.speed, accuracy: 0.5)
    }

    func testRebuildCountsTheDrawnStreet() {
        let street = StreetSegment(id: "s", name: "s", points: [a, b], lengthMeters: Geo.distance(a, b), district: "Praha 1")
        let graph = StreetGraph(segments: ["s": street])
        let matcher = MapMatcher(graph: graph)
        let fixes = DrawnWalk.fixes(strokes: [[a, b]], start: start)
        let counts = CoverageRebuild.passCounts(fixes: fixes, graph: graph, matcher: matcher, hmm: HMMMatcher(graph: graph, matcher: matcher))
        XCTAssertEqual(counts, ["s": 1])
    }
}

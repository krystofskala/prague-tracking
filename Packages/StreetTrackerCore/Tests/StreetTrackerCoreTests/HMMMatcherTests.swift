import XCTest
@testable import StreetTrackerCore

final class HMMMatcherTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    /// 15 m east at latitude 50.
    private let parallel = 15.0 / 71_700

    private func segment(_ id: String, _ points: [Coordinate]) -> StreetSegment {
        StreetSegment(id: id, name: id, points: points, lengthMeters: Geo.polylineLength(points), district: "Praha 1")
    }

    /// "a" north along 14.4, "b" 15 m east of it, "c" east from a's end.
    private func graph() -> StreetGraph {
        let top = Coordinate(latitude: 50.002, longitude: 14.4)
        return StreetGraph(segments: [
            "a": segment("a", [Coordinate(latitude: 50.0, longitude: 14.4), top]),
            "b": segment("b", [Coordinate(latitude: 50.0, longitude: 14.4 + parallel),
                               Coordinate(latitude: 50.0018, longitude: 14.4 + parallel)]),
            "c": segment("c", [top, Coordinate(latitude: 50.002, longitude: 14.403)]),
        ])
    }

    private func fix(_ i: Int, _ lat: Double, _ lon: Double) -> Fix {
        Fix(time: t0.addingTimeInterval(Double(i) * 3), coordinate: Coordinate(latitude: lat, longitude: lon))
    }

    func testCandidatesAreSortedByDistance() {
        let g = graph()
        let c = MapMatcher(graph: g).candidates(Coordinate(latitude: 50.001, longitude: 14.4 + parallel * 0.3))
        XCTAssertEqual(c.map(\.segmentID), ["a", "b"])
        XCTAssertEqual(MapMatcher(graph: g).match(Coordinate(latitude: 50.001, longitude: 14.4 + parallel * 0.3))?.segmentID, "a")
    }

    func testNoisyFixesStayOnOneOfTwoParallelStreets() {
        let g = graph()
        let matcher = MapMatcher(graph: g)
        // Walking up "a"; every fourth fix drifts 9 m east, nearer to "b".
        let fixes = (0..<15).map { i in
            fix(i, 50.0002 + Double(i) * 0.0001, 14.4 + parallel * (i % 4 == 2 ? 0.6 : 0.1))
        }
        XCTAssertTrue(fixes.contains { matcher.match($0.coordinate)?.segmentID == "b" }, "nearest street jumps")
        let matched = HMMMatcher(graph: g, matcher: matcher).match(fixes)
        XCTAssertEqual(Set(matched.compactMap { $0?.segmentID }), ["a"])
    }

    func testTurnsAtACrossing() {
        let g = graph()
        let up = (0..<5).map { i in fix(i, 50.0016 + Double(i) * 0.0001, 14.4) }
        let east = (1...5).map { i in fix(5 + i, 50.002, 14.4 + Double(i) * 0.0003) }
        let matched = HMMMatcher(graph: g, matcher: MapMatcher(graph: g)).match(up + east)
        XCTAssertEqual(matched.map { $0?.segmentID }, Array(repeating: "a", count: 5) + Array(repeating: "c", count: 5))
    }

    func testFixFarFromStreetsIsNilAndSplitsTheChain() {
        let g = graph()
        let fixes = [fix(0, 50.0005, 14.4), fix(1, 50.0005, 14.41), fix(2, 50.0006, 14.4)]
        let matched = HMMMatcher(graph: g, matcher: MapMatcher(graph: g)).match(fixes)
        XCTAssertEqual(matched.map { $0?.segmentID }, ["a", nil, "a"])
    }

    func testRebuildWithHMMCountsOnlyTheWalkedStreet() {
        let g = graph()
        let matcher = MapMatcher(graph: g)
        let fixes = (0..<15).map { i in
            Fix(time: t0.addingTimeInterval(Double(i) * 3),
                coordinate: Coordinate(latitude: 50.0002 + Double(i) * 0.0001, longitude: 14.4 + parallel * (i % 2 == 1 ? 0.6 : 0.1)))
        }
        let nearest = CoverageRebuild.passCounts(fixes: fixes, graph: g, matcher: matcher)
        XCTAssertEqual(nearest["b"], 1, "zig-zag noise counts the parallel street without HMM")
        let hmm = CoverageRebuild.passCounts(fixes: fixes, graph: g, matcher: matcher, hmm: HMMMatcher(graph: g, matcher: matcher))
        XCTAssertEqual(hmm, ["a": 1])
    }
}

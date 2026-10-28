import XCTest
@testable import StreetTrackerCore

final class WalkEditTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    /// A fix every 10 s, ~11 m north each, along longitude 14.4.
    private func fixes(_ range: ClosedRange<Int>, lon: Double = 14.4) -> [Fix] {
        range.map { i in
            Fix(time: t0.addingTimeInterval(Double(i) * 10),
                coordinate: Coordinate(latitude: 50.0 + Double(i) * 0.0001, longitude: lon))
        }
    }

    private func segment(_ id: String, _ points: [(Double, Double)]) -> StreetSegment {
        let coords = points.map { Coordinate(latitude: $0.0, longitude: $0.1) }
        let length = zip(coords, coords.dropFirst()).reduce(0) { $0 + Geo.distance($1.0, $1.1) }
        return StreetSegment(id: id, name: id, points: coords, lengthMeters: length, district: nil)
    }

    func testRemovedPieceSplitsSegment() {
        let walk = Walk(id: "w", segments: [fixes(0...29)])
        let edit = WalkEdit(removed: [TimeRange(from: t0.addingTimeInterval(95), to: t0.addingTimeInterval(155))])
        let edited = walk.applying(edit)!
        XCTAssertEqual(edited.segments.map(\.count), [10, 14])
        XCTAssertLessThan(edited.distanceMeters, walk.distanceMeters)
    }

    func testTrimAndUndo() {
        let walk = Walk(id: "w", segments: [fixes(0...29)])
        let edit = WalkEdit(trimStart: t0.addingTimeInterval(50), trimEnd: t0.addingTimeInterval(200))
        let edited = walk.applying(edit)!
        XCTAssertEqual(edited.start, t0.addingTimeInterval(50))
        XCTAssertEqual(edited.end, t0.addingTimeInterval(200))
        XCTAssertEqual(walk.applying(nil), walk)
        XCTAssertEqual(walk.applying(WalkEdit()), walk)
    }

    func testEverythingRemovedGivesNil() {
        let walk = Walk(id: "w", segments: [fixes(0...5)])
        XCTAssertNil(walk.applying(WalkEdit(trimStart: t0.addingTimeInterval(1000))))
    }

    func testExcludedRangesCoverTrims() {
        let walk = Walk(id: "w", segments: [fixes(0...29)])
        let edit = WalkEdit(trimStart: t0.addingTimeInterval(50), trimEnd: t0.addingTimeInterval(200))
        let ranges = edit.excludedRanges(of: walk)
        for fix in walk.fixes {
            XCTAssertEqual(ranges.contains { $0.contains(fix.time) }, !edit.keeps(fix.time))
        }
    }

    func testDrawnPieceGoesIntoDistanceAndGPX() {
        let drawn = [Coordinate(latitude: 50.01, longitude: 14.4), Coordinate(latitude: 50.011, longitude: 14.4)]
        let walk = Walk(id: "w", segments: [fixes(0...5)]).applying(WalkEdit(drawn: [drawn]))!
        XCTAssertEqual(walk.drawn.count, 1)
        XCTAssertGreaterThan(walk.distanceMeters, 100)
        let gpx = GPX.write(walk, name: "test")
        XCTAssertEqual(gpx.components(separatedBy: "<trkseg>").count - 1, 2)
        XCTAssertEqual(GPX.read(Data(gpx.utf8)).count, 2)
    }

    func testMetaWithoutEditStillDecodes() throws {
        let old = ##"{"title":"Večer","tags":["vecer"],"color":"#ff0000"}"##
        let meta = try JSONDecoder().decode(WalkMeta.self, from: Data(old.utf8))
        XCTAssertNil(meta.edit)
        XCTAssertEqual(meta.tags, ["vecer"])
    }

    // MARK: Rebuild

    private func graph() -> StreetGraph {
        StreetGraph(segments: [
            "north": segment("north", [(50.0, 14.4), (50.003, 14.4)]),
            "east": segment("east", [(50.01, 14.41), (50.01, 14.412)]),
            "tiny": segment("tiny", [(50.02, 14.42), (50.0201, 14.42)]),
        ])
    }

    func testRebuildCountsLikeLiveTracking() {
        let g = graph()
        let counts = CoverageRebuild.passCounts(fixes: fixes(0...29), graph: g, matcher: MapMatcher(graph: g))
        XCTAssertEqual(counts["north"], 1)
        XCTAssertNil(counts["east"])
    }

    func testExcludedFixesDoNotCount() {
        let g = graph()
        let all = TimeRange(from: t0, to: t0.addingTimeInterval(1000))
        let counts = CoverageRebuild.passCounts(fixes: fixes(0...29), excluded: [all], graph: g, matcher: MapMatcher(graph: g))
        XCTAssertNil(counts["north"])
    }

    func testDrawnManualAndLegacy() {
        let g = graph()
        let drawn = [[Coordinate(latitude: 50.01, longitude: 14.41), Coordinate(latitude: 50.01, longitude: 14.412)]]
        let counts = CoverageRebuild.passCounts(
            fixes: [], drawn: drawn, manualSegments: ["tiny"], legacy: ["north": 3],
            graph: g, matcher: MapMatcher(graph: g)
        )
        XCTAssertEqual(counts["east"], 1)
        XCTAssertEqual(counts["tiny"], 1)
        XCTAssertEqual(counts["north"], 3)
    }

    func testSnapLandsOnStreet() {
        let g = graph()
        let matcher = MapMatcher(graph: g)
        // 10 m east of the north street.
        let snapped = matcher.snap(Coordinate(latitude: 50.001, longitude: 14.40014))!
        XCTAssertEqual(snapped.longitude, 14.4, accuracy: 1e-7)
        XCTAssertEqual(snapped.latitude, 50.001, accuracy: 1e-7)
        XCTAssertNil(matcher.snap(Coordinate(latitude: 50.5, longitude: 14.9)))
    }

    func testLegacyIsWhatTheLogCannotExplain() {
        let legacy = CoverageRebuild.legacyCounts(current: ["a": 5, "b": 1, "c": 2], fromLog: ["a": 2, "b": 1, "c": 4])
        XCTAssertEqual(legacy, ["a": 3])
    }
}

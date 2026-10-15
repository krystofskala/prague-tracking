import Foundation
import XCTest
@testable import StreetTrackerCore

/// Sanity + timing check of the real Prague data bundled with the app
/// (App/Resources). Catches a bad Overpass download (empty / truncated) and
/// districts that RingAssembler can't close, and prints how long launch-time
/// loading takes. Skipped while the repo only has the tiny demo fixture.
final class BundledDataTests: XCTestCase {
    private static let resources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // StreetTrackerCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // StreetTrackerCore
        .deletingLastPathComponent() // Packages
        .deletingLastPathComponent() // repo root
        .appendingPathComponent("App/Resources")

    func testFullPragueDataLoadsAndIsTaggedWithDistricts() throws {
        let streetsData = try Data(contentsOf: Self.resources.appendingPathComponent("prague_streets.json"))
        let districtsData = try Data(contentsOf: Self.resources.appendingPathComponent("prague_districts.json"))
        try XCTSkipIf(streetsData.count < 1_000_000, "only the demo fixture is bundled")

        var start = Date()
        let graph = try OSMLoader.loadGraph(fromOverpassJSON: streetsData)
        let loadSeconds = Date().timeIntervalSince(start)

        start = Date()
        let boundaries = try DistrictTagger.loadBoundaries(fromOverpassJSON: districtsData)
        let tagged = DistrictTagger.tag(graph: graph, with: boundaries)
        let tagSeconds = Date().timeIntervalSince(start)

        let withDistrict = tagged.segments.values.filter { $0.district != nil }.count
        let districtNames = Set(tagged.segments.values.compactMap(\.district))
        print(String(format: "Prague data: %d segments, %d/%d districts used, %d untagged; load %.2f s, districts %.2f s",
                     graph.segments.count, districtNames.count, boundaries.count,
                     graph.segments.count - withDistrict, loadSeconds, tagSeconds))

        XCTAssertGreaterThan(graph.segments.count, 20_000)
        XCTAssertGreaterThanOrEqual(boundaries.count, 100, "Prague has 112 katastrální území")
        XCTAssertGreaterThan(Double(withDistrict) / Double(graph.segments.count), 0.98)

        // Hot paths on the real graph: matching runs on every GPS fix,
        // suggestions on a button tap.
        start = Date()
        let matcher = MapMatcher(graph: tagged)
        let indexSeconds = Date().timeIntervalSince(start)
        let malostranske = Coordinate(latitude: 50.0880, longitude: 14.4035)
        start = Date()
        var matched = 0
        for i in 0..<1_000 {
            let point = Coordinate(latitude: malostranske.latitude + Double(i % 40) * 0.0001,
                                   longitude: malostranske.longitude + Double(i / 40) * 0.0001)
            if matcher.match(point) != nil { matched += 1 }
        }
        let matchMillis = Date().timeIntervalSince(start) * 1000 / 1_000
        start = Date()
        let suggestions = RouteSuggester.nearestUnwalked(from: malostranske, graph: tagged, coverage: CoverageStore())
        let suggestMillis = Date().timeIntervalSince(start) * 1000
        print(String(format: "Hot paths: index %.2f s, match %.3f ms/fix (%d/1000 matched), suggestions %.0f ms",
                     indexSeconds, matchMillis, matched, suggestMillis))
        XCTAssertEqual(suggestions.count, 20)
        XCTAssertGreaterThan(matched, 500)

        // The grid index must not miss anything: compare with a brute-force
        // scan of every segment for a sample of points.
        for i in stride(from: 0, to: 1_000, by: 37) {
            let point = Coordinate(latitude: malostranske.latitude + Double(i % 40) * 0.0001,
                                   longitude: malostranske.longitude + Double(i / 40) * 0.0001)
            var bruteBest = Double.greatestFiniteMagnitude
            for segment in tagged.segments.values {
                for (a, b) in zip(segment.points, segment.points.dropFirst()) {
                    let d = Geo.pointToSegmentDistance(p: Geo.toLocalMeters(point, origin: point),
                                                       a: Geo.toLocalMeters(a, origin: point),
                                                       b: Geo.toLocalMeters(b, origin: point))
                    bruteBest = min(bruteBest, d)
                }
            }
            let indexed = matcher.match(point)
            if bruteBest <= matcher.maxMatchDistanceMeters {
                XCTAssertEqual(indexed?.distanceMeters ?? .infinity, bruteBest, accuracy: 0.01, "point \(i)")
            } else {
                XCTAssertNil(indexed, "point \(i)")
            }
        }
    }
}

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
    }
}

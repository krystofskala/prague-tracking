import XCTest
@testable import StreetTrackerCore

final class RouteSuggesterTests: XCTestCase {
    private func makeGraph() -> StreetGraph {
        let near = StreetSegment(id: "near", name: "Near St", points: [
            Coordinate(latitude: 50.0801, longitude: 14.4001),
            Coordinate(latitude: 50.0802, longitude: 14.4001)
        ], lengthMeters: 50, district: "Malá Strana")
        let far = StreetSegment(id: "far", name: "Far St", points: [
            Coordinate(latitude: 50.2000, longitude: 14.6000),
            Coordinate(latitude: 50.2010, longitude: 14.6000)
        ], lengthMeters: 50, district: "Suchdol")
        let walked = StreetSegment(id: "walked", name: "Walked St", points: [
            Coordinate(latitude: 50.0800, longitude: 14.4000),
            Coordinate(latitude: 50.0801, longitude: 14.4000)
        ], lengthMeters: 50, district: "Malá Strana")
        return StreetGraph(segments: ["near": near, "far": far, "walked": walked])
    }

    func testNearestUnwalkedExcludesWalkedSegments() {
        let coverage = CoverageStore()
        coverage.recordPass(segmentID: "walked")
        let origin = Coordinate(latitude: 50.0800, longitude: 14.4000)

        let suggestions = RouteSuggester.nearestUnwalked(from: origin, graph: makeGraph(), coverage: coverage)

        XCTAssertFalse(suggestions.contains { $0.segmentID == "walked" })
        XCTAssertEqual(suggestions.first?.segmentID, "near")
    }

    func testNearestUnwalkedIsSortedByDistance() {
        let coverage = CoverageStore()
        let origin = Coordinate(latitude: 50.0800, longitude: 14.4000)

        let suggestions = RouteSuggester.nearestUnwalked(from: origin, graph: makeGraph(), coverage: coverage)

        XCTAssertEqual(suggestions.map(\.segmentID), ["walked", "near", "far"])
    }

    func testStreetSplitIntoSeveralWaysIsListedOnce() {
        var graph = makeGraph()
        graph.segments["near2"] = StreetSegment(id: "near2", name: "Near St", points: [
            Coordinate(latitude: 50.0802, longitude: 14.4001),
            Coordinate(latitude: 50.0803, longitude: 14.4001)
        ], lengthMeters: 11, district: "Malá Strana")
        let origin = Coordinate(latitude: 50.0800, longitude: 14.4000)

        let suggestions = RouteSuggester.nearestUnwalked(from: origin, graph: graph, coverage: CoverageStore())

        XCTAssertEqual(suggestions.map(\.segmentID), ["walked", "near", "far"])
    }

    func testLeastCompleteDistrictPicksLowestCoverage() {
        let coverage = CoverageStore()
        coverage.recordPass(segmentID: "walked") // Malá Strana: 1 of 2 segments' length walked
        let district = RouteSuggester.leastCompleteDistrict(graph: makeGraph(), coverage: coverage)
        XCTAssertEqual(district, "Suchdol") // 0% walked, strictly less than Malá Strana's 50%
    }
}

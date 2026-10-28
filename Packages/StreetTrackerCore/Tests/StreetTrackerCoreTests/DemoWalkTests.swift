import XCTest
@testable import StreetTrackerCore

final class DemoWalkTests: XCTestCase {
    private func segment(_ id: String, _ points: [(Double, Double)]) -> StreetSegment {
        let coords = points.map { Coordinate(latitude: $0.0, longitude: $0.1) }
        let length = zip(coords, coords.dropFirst()).reduce(0) { $0 + Geo.distance($1.0, $1.1) }
        return StreetSegment(id: id, name: id, points: coords, lengthMeters: length, district: nil)
    }

    func testFollowsConnectedStreetsWithSmallSteps() {
        let graph = StreetGraph(segments: [
            "a": segment("a", [(50.0, 14.0), (50.0, 14.001)]),
            // Stored backwards, so the walk has to turn it around.
            "b": segment("b", [(50.001, 14.001), (50.0, 14.001)]),
            "far": segment("far", [(50.01, 14.01), (50.011, 14.01)]),
        ])
        let route = DemoWalk.route(in: graph, from: Coordinate(latitude: 50.0, longitude: 14.0))
        XCTAssertEqual(route.first!.latitude, 50.0, accuracy: 1e-9)
        XCTAssertEqual(route.last!.latitude, 50.001, accuracy: 1e-9)
        for (p, q) in zip(route, route.dropFirst()) {
            XCTAssertLessThanOrEqual(Geo.distance(p, q), 4.01)
        }
        XCTAssertFalse(route.contains { $0.latitude > 50.005 })
    }

    func testEmptyGraphGivesEmptyRoute() {
        XCTAssertTrue(DemoWalk.route(in: StreetGraph(segments: [:])).isEmpty)
    }
}

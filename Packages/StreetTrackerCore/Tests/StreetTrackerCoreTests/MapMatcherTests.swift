import XCTest
@testable import StreetTrackerCore

final class MapMatcherTests: XCTestCase {
    /// Two short, parallel, north-south streets ~30m apart, plus one
    /// perpendicular cross street, roughly centered near Malostranské náměstí.
    private func makeTestGraph() -> StreetGraph {
        let streetA = StreetSegment(
            id: "A",
            name: "Ulice A",
            points: [
                Coordinate(latitude: 50.0880, longitude: 14.4030),
                Coordinate(latitude: 50.0885, longitude: 14.4030)
            ],
            lengthMeters: 55,
            district: "Malá Strana"
        )
        let streetB = StreetSegment(
            id: "B",
            name: "Ulice B",
            points: [
                Coordinate(latitude: 50.0880, longitude: 14.4034),
                Coordinate(latitude: 50.0885, longitude: 14.4034)
            ],
            lengthMeters: 55,
            district: "Malá Strana"
        )
        let cross = StreetSegment(
            id: "C",
            name: "Cross Street",
            points: [
                Coordinate(latitude: 50.0880, longitude: 14.4030),
                Coordinate(latitude: 50.0880, longitude: 14.4034)
            ],
            lengthMeters: 28,
            district: "Malá Strana"
        )
        return StreetGraph(segments: ["A": streetA, "B": streetB, "C": cross])
    }

    func testMatchesPointExactlyOnSegment() {
        let matcher = MapMatcher(graph: makeTestGraph())
        let onA = Coordinate(latitude: 50.0882, longitude: 14.4030)
        let result = matcher.match(onA)
        XCTAssertEqual(result?.segmentID, "A")
        XCTAssertLessThan(result?.distanceMeters ?? .infinity, 1.0)
    }

    func testMatchesNearbyPointToClosestSegment() {
        let matcher = MapMatcher(graph: makeTestGraph())
        // Slightly closer to B than A.
        let nearB = Coordinate(latitude: 50.0882, longitude: 14.4033)
        let result = matcher.match(nearB)
        XCTAssertEqual(result?.segmentID, "B")
    }

    func testReturnsNilWhenTooFarFromAnySegment() {
        let matcher = MapMatcher(graph: makeTestGraph(), maxMatchDistanceMeters: 25)
        let farAway = Coordinate(latitude: 50.1200, longitude: 14.5000)
        XCTAssertNil(matcher.match(farAway))
    }

    func testEmptyGraphNeverMatches() {
        let matcher = MapMatcher(graph: StreetGraph(segments: [:]))
        XCTAssertNil(matcher.match(Coordinate(latitude: 50.0882, longitude: 14.4030)))
    }

    /// A long straight street with no nodes in between (common in OSM: ~1,100
    /// Prague streets have an edge longer than 150 m). A fix in the middle is
    /// far from both endpoints, so the grid index must cover the whole edge,
    /// not just the cells that contain vertices.
    func testMatchesMiddleOfLongStraightEdge() {
        let long = StreetSegment(
            id: "L",
            name: "Dlouhá rovná",
            points: [
                Coordinate(latitude: 50.0800, longitude: 14.4000),
                Coordinate(latitude: 50.0800, longitude: 14.4100) // ~715 m east
            ],
            lengthMeters: 715,
            district: nil
        )
        let matcher = MapMatcher(graph: StreetGraph(segments: ["L": long]))
        let middle = Coordinate(latitude: 50.08005, longitude: 14.4050) // ~5 m north of the line
        XCTAssertEqual(matcher.match(middle)?.segmentID, "L")
    }

    /// Long diagonal edges: sampling an edge every half cell can skip the
    /// corner of a cell it clips; the 3x3 neighbourhood search must still
    /// find it. Checked against brute force at points 5-20 m off the line.
    func testLongDiagonalEdgesMatchBruteForce() {
        let edges = [
            (Coordinate(latitude: 50.0700, longitude: 14.4000), Coordinate(latitude: 50.0745, longitude: 14.4093)),
            (Coordinate(latitude: 50.0800, longitude: 14.4300), Coordinate(latitude: 50.0751, longitude: 14.4371)),
            (Coordinate(latitude: 50.0900, longitude: 14.4500), Coordinate(latitude: 50.0961, longitude: 14.4519))
        ]
        var segments: [String: StreetSegment] = [:]
        for (n, edge) in edges.enumerated() {
            segments["\(n)"] = StreetSegment(id: "\(n)", name: nil, points: [edge.0, edge.1],
                                              lengthMeters: Geo.distance(edge.0, edge.1), district: nil)
        }
        let matcher = MapMatcher(graph: StreetGraph(segments: segments))
        for (n, edge) in edges.enumerated() {
            for step in 1..<20 {
                let t = Double(step) / 20
                for offsetDegrees in [0.00005, -0.00012, 0.00018] { // ~5-20 m off the line
                    let point = Coordinate(
                        latitude: edge.0.latitude + (edge.1.latitude - edge.0.latitude) * t + offsetDegrees,
                        longitude: edge.0.longitude + (edge.1.longitude - edge.0.longitude) * t
                    )
                    let local = Geo.toLocalMeters(point, origin: point)
                    let brute = Geo.pointToSegmentDistance(p: local, a: Geo.toLocalMeters(edge.0, origin: point),
                                                           b: Geo.toLocalMeters(edge.1, origin: point))
                    let result = matcher.match(point)
                    if brute <= matcher.maxMatchDistanceMeters {
                        XCTAssertEqual(result?.segmentID, "\(n)", "edge \(n) t=\(t) offset \(offsetDegrees)")
                    } else {
                        XCTAssertNil(result)
                    }
                }
            }
        }
    }
}

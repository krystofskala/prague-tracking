import XCTest
@testable import StreetTrackerCore

final class DistrictTaggerTests: XCTestCase {
    private let sampleJSON = """
    {
      "elements": [
        {
          "type": "relation",
          "id": 9001,
          "tags": { "name": "Malá Strana" },
          "members": [
            {
              "type": "way",
              "ref": 1,
              "role": "outer",
              "geometry": [
                { "lat": 50.000, "lon": 14.000 },
                { "lat": 50.000, "lon": 14.010 },
                { "lat": 50.010, "lon": 14.010 },
                { "lat": 50.010, "lon": 14.000 },
                { "lat": 50.000, "lon": 14.000 }
              ]
            }
          ]
        }
      ]
    }
    """.data(using: .utf8)!

    func testLoadsBoundaryFromRelation() throws {
        let boundaries = try DistrictTagger.loadBoundaries(fromOverpassJSON: sampleJSON)
        XCTAssertEqual(boundaries.count, 1)
        XCTAssertEqual(boundaries.first?.name, "Malá Strana")
        XCTAssertEqual(boundaries.first?.rings.first?.count, 5)
    }

    func testPointInPolygonInsideAndOutside() throws {
        let boundaries = try DistrictTagger.loadBoundaries(fromOverpassJSON: sampleJSON)
        let ring = try XCTUnwrap(boundaries.first?.rings.first)

        let inside = Coordinate(latitude: 50.005, longitude: 14.005)
        let outside = Coordinate(latitude: 50.500, longitude: 14.500)

        XCTAssertTrue(DistrictTagger.pointInPolygon(inside, ring))
        XCTAssertFalse(DistrictTagger.pointInPolygon(outside, ring))
    }

    func testTagAssignsDistrictToSegmentsInsideBoundary() throws {
        let boundaries = try DistrictTagger.loadBoundaries(fromOverpassJSON: sampleJSON)

        let insideSegment = StreetSegment(
            id: "in",
            name: "Inside St",
            points: [
                Coordinate(latitude: 50.004, longitude: 14.004),
                Coordinate(latitude: 50.006, longitude: 14.006)
            ],
            lengthMeters: 100,
            district: nil
        )
        let outsideSegment = StreetSegment(
            id: "out",
            name: "Outside St",
            points: [
                Coordinate(latitude: 50.500, longitude: 14.500),
                Coordinate(latitude: 50.501, longitude: 14.501)
            ],
            lengthMeters: 100,
            district: nil
        )
        let graph = StreetGraph(segments: ["in": insideSegment, "out": outsideSegment])

        let tagged = DistrictTagger.tag(graph: graph, with: boundaries)

        XCTAssertEqual(tagged.segments["in"]?.district, "Malá Strana")
        XCTAssertNil(tagged.segments["out"]?.district)
    }

    func testEnclaveDistrictWinsOverSurroundingOne() {
        // Josefov sits inside Staré Město; both outer rings contain its streets.
        func square(_ lat: Double, _ lon: Double, _ size: Double) -> [Coordinate] {
            [Coordinate(latitude: lat, longitude: lon),
             Coordinate(latitude: lat + size, longitude: lon),
             Coordinate(latitude: lat + size, longitude: lon + size),
             Coordinate(latitude: lat, longitude: lon + size),
             Coordinate(latitude: lat, longitude: lon)]
        }
        let stareMesto = DistrictBoundary(name: "Staré Město", rings: [square(50.08, 14.41, 0.02)])
        let josefov = DistrictBoundary(name: "Josefov", rings: [square(50.088, 14.418, 0.004)])
        let inJosefov = StreetSegment(id: "j", name: "Široká", points: [
            Coordinate(latitude: 50.089, longitude: 14.419), Coordinate(latitude: 50.090, longitude: 14.420)
        ], lengthMeters: 130, district: nil)
        let elsewhere = StreetSegment(id: "s", name: "Celetná", points: [
            Coordinate(latitude: 50.082, longitude: 14.412), Coordinate(latitude: 50.083, longitude: 14.413)
        ], lengthMeters: 130, district: nil)
        let graph = StreetGraph(segments: ["j": inJosefov, "s": elsewhere])

        for order in [[stareMesto, josefov], [josefov, stareMesto]] {
            let tagged = DistrictTagger.tag(graph: graph, with: order)
            XCTAssertEqual(tagged.segments["j"]?.district, "Josefov")
            XCTAssertEqual(tagged.segments["s"]?.district, "Staré Město")
        }
    }
}

import Foundation

public struct DistrictBoundary: Sendable {
    public let name: String
    /// One or more closed outer rings — a district can be non-contiguous.
    public let rings: [[Coordinate]]

    public init(name: String, rings: [[Coordinate]]) {
        self.name = name
        self.rings = rings
    }
}

/// Tags street segments with the Prague cadastral district (e.g. "Malá
/// Strana") they fall in, so coverage can be reported per-district instead
/// of just city-wide.
///
/// Consumes the same Overpass API JSON style as `OSMLoader` (queried with
/// `out geom;` so each relation member way carries its own coordinates
/// inline) rather than GeoJSON, to keep a single data pipeline through the
/// app. See Scripts/fetch_prague_districts.sh for the query.
public enum DistrictTagger {
    public enum LoaderError: Error {
        case decodingFailed(Error)
    }

    public static func loadBoundaries(fromOverpassJSON data: Data) throws -> [DistrictBoundary] {
        let decoded: OverpassGeomResponse
        do {
            decoded = try JSONDecoder().decode(OverpassGeomResponse.self, from: data)
        } catch {
            throw LoaderError.decodingFailed(error)
        }

        var boundaries: [DistrictBoundary] = []
        for relation in decoded.elements where relation.type == "relation" {
            guard let name = relation.tags?["name"] else { continue }
            let outerWays = (relation.members ?? [])
                .filter { $0.role == "outer" }
                .compactMap { $0.geometry }
                .map { points in points.map { Coordinate(latitude: $0.lat, longitude: $0.lon) } }

            let rings = RingAssembler.assembleClosedRings(from: outerWays)
            guard !rings.isEmpty else { continue }
            boundaries.append(DistrictBoundary(name: name, rings: rings))
        }
        return boundaries
    }

    /// Returns a copy of `graph` with `district` filled in on every segment
    /// whose representative point falls inside one of `boundaries`. Segments
    /// that don't match any boundary are left unchanged (district stays nil).
    public static func tag(graph: StreetGraph, with boundaries: [DistrictBoundary]) -> StreetGraph {
        // Bounding-box pre-check per ring: the full Prague graph is ~32k
        // segments against 112 districts, and this runs at app launch, so
        // skip the ray cast for rings that can't possibly contain the point.
        let indexed = boundaries.map { boundary in
            (name: boundary.name, rings: boundary.rings.map { (box: BoundingBox($0), ring: $0) })
        }
        var result = graph
        for (id, segment) in graph.segments {
            let representative = segment.points[segment.points.count / 2]
            // Smallest containing ring wins: Josefov is an enclave inside
            // Staré Město, whose relation lists it as an `inner` ring that
            // RingAssembler ignores, so both outer rings contain its streets.
            var match: (name: String, area: Double)?
            for boundary in indexed {
                for ring in boundary.rings
                where ring.box.contains(representative) && pointInPolygon(representative, ring.ring) {
                    if ring.box.area < (match?.area ?? .infinity) {
                        match = (boundary.name, ring.box.area)
                    }
                }
            }
            guard let match else { continue }

            result.segments[id] = StreetSegment(
                id: segment.id,
                name: segment.name,
                points: segment.points,
                lengthMeters: segment.lengthMeters,
                district: match.name
            )
        }
        return result
    }

    struct BoundingBox {
        let minLat, maxLat, minLon, maxLon: Double

        init(_ ring: [Coordinate]) {
            minLat = ring.map(\.latitude).min() ?? 0
            maxLat = ring.map(\.latitude).max() ?? 0
            minLon = ring.map(\.longitude).min() ?? 0
            maxLon = ring.map(\.longitude).max() ?? 0
        }

        var area: Double { (maxLat - minLat) * (maxLon - minLon) }

        func contains(_ point: Coordinate) -> Bool {
            point.latitude >= minLat && point.latitude <= maxLat
                && point.longitude >= minLon && point.longitude <= maxLon
        }
    }

    /// Standard ray-casting point-in-polygon test.
    static func pointInPolygon(_ point: Coordinate, _ polygon: [Coordinate]) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let pi = polygon[i]
            let pj = polygon[j]
            if (pi.latitude > point.latitude) != (pj.latitude > point.latitude),
               point.longitude < (pj.longitude - pi.longitude) * (point.latitude - pi.latitude)
                   / (pj.latitude - pi.latitude) + pi.longitude {
                inside.toggle()
            }
            j = i
        }
        return inside
    }
}

struct OverpassGeomResponse: Codable {
    let elements: [OverpassGeomElement]
}

struct OverpassGeomElement: Codable {
    let type: String
    let id: Int64?
    let tags: [String: String]?
    let members: [OverpassGeomMember]?
}

struct OverpassGeomMember: Codable {
    let type: String
    let ref: Int64?
    let role: String?
    let geometry: [OverpassGeomPoint]?
}

struct OverpassGeomPoint: Codable {
    let lat: Double
    let lon: Double
}

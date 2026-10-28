import Foundation

/// A plain lat/lon pair. Kept independent of CoreLocation so this package
/// has zero Apple-framework dependencies and can be unit tested anywhere.
public struct Coordinate: Codable, Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Geometry helpers shared by map matching, coverage, and route suggestion.
public enum Geo {
    public static let earthRadiusMeters = 6_371_000.0

    /// Great-circle distance between two coordinates, in meters.
    public static func distance(_ a: Coordinate, _ b: Coordinate) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let sinDLat = sin(dLat / 2)
        let sinDLon = sin(dLon / 2)
        let h = sinDLat * sinDLat + cos(lat1) * cos(lat2) * sinDLon * sinDLon
        let c = 2 * atan2(sqrt(h), sqrt(1 - h))
        return earthRadiusMeters * c
    }

    public static func polylineLength(_ points: [Coordinate]) -> Double {
        guard points.count >= 2 else { return 0 }
        var total = 0.0
        for i in 1..<points.count {
            total += distance(points[i - 1], points[i])
        }
        return total
    }

    /// Cheap equirectangular projection to local meters, good enough for
    /// point-to-segment math at city scale (errors are sub-meter over a
    /// few hundred meters, which is well within GPS noise).
    public static func toLocalMeters(_ point: Coordinate, origin: Coordinate) -> (x: Double, y: Double) {
        let latRad = origin.latitude * .pi / 180
        let x = (point.longitude - origin.longitude) * .pi / 180 * earthRadiusMeters * cos(latRad)
        let y = (point.latitude - origin.latitude) * .pi / 180 * earthRadiusMeters
        return (x, y)
    }

    public static func fromLocalMeters(_ p: (x: Double, y: Double), origin: Coordinate) -> Coordinate {
        let latRad = origin.latitude * .pi / 180
        return Coordinate(
            latitude: origin.latitude + p.y / earthRadiusMeters * 180 / .pi,
            longitude: origin.longitude + p.x / (earthRadiusMeters * cos(latRad)) * 180 / .pi
        )
    }

    /// Nearest point of the segment `[a, b]` to `p`, all in local meters.
    public static func projection(
        p: (x: Double, y: Double),
        a: (x: Double, y: Double),
        b: (x: Double, y: Double)
    ) -> (x: Double, y: Double) {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return a }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return (a.x + t * dx, a.y + t * dy)
    }

    /// Shortest distance from point `p` to the segment `[a, b]`, all in local meters.
    public static func pointToSegmentDistance(
        p: (x: Double, y: Double),
        a: (x: Double, y: Double),
        b: (x: Double, y: Double)
    ) -> Double {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        if lengthSquared == 0 {
            let ex = p.x - a.x, ey = p.y - a.y
            return (ex * ex + ey * ey).squareRoot()
        }
        var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared
        t = max(0, min(1, t))
        let projX = a.x + t * dx
        let projY = a.y + t * dy
        let ex = p.x - projX, ey = p.y - projY
        return (ex * ex + ey * ey).squareRoot()
    }
}

import Foundation

/// A made-up walk along real streets of the bundled graph, for screenshots
/// and UI tests on the simulator. Never uses recorded data.
public enum DemoWalk {
    /// Old Town Square.
    public static let defaultStart = Coordinate(latitude: 50.0875, longitude: 14.4213)

    /// Follows connected segments from the one nearest `start`, never using
    /// a segment twice, until `maxMeters` is walked or the streets run out.
    /// Points are `step` metres apart, like fixes at walking pace.
    public static func route(in graph: StreetGraph, from start: Coordinate = defaultStart,
                             maxMeters: Double = 2500, step: Double = 4,
                             joinDistance: Double = 15) -> [Coordinate] {
        let named = graph.segments.values.filter { $0.points.count >= 2 }
        guard var current = named.min(by: { nearest($0, start) < nearest($1, start) }) else { return [] }
        var used: Set<String> = [current.id]
        var points = Geo.distance(current.points.first!, start) <= Geo.distance(current.points.last!, start)
            ? current.points : current.points.reversed()
        var walked = length(points)
        while walked < maxMeters, let end = points.last {
            // Prefer the next segment closest to where we are.
            let next = named
                .filter { !used.contains($0.id) }
                .map { segment -> (StreetSegment, Bool, Double) in
                    let toFirst = Geo.distance(segment.points.first!, end)
                    let toLast = Geo.distance(segment.points.last!, end)
                    return (segment, toFirst <= toLast, min(toFirst, toLast))
                }
                .filter { $0.2 <= joinDistance }
                .min { $0.2 < $1.2 }
            guard let (segment, forward, _) = next else { break }
            current = segment
            used.insert(segment.id)
            let more = forward ? segment.points : segment.points.reversed()
            walked += length(more)
            points += more
        }
        return densify(points, step: step)
    }

    private static func nearest(_ segment: StreetSegment, _ point: Coordinate) -> Double {
        segment.points.map { Geo.distance($0, point) }.min() ?? .infinity
    }

    private static func length(_ points: [Coordinate]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + Geo.distance($1.0, $1.1) }
    }

    private static func densify(_ points: [Coordinate], step: Double) -> [Coordinate] {
        guard let first = points.first else { return [] }
        var result = [first]
        for (a, b) in zip(points, points.dropFirst()) {
            let parts = max(1, Int((Geo.distance(a, b) / step).rounded(.up)))
            for i in 1...parts {
                let t = Double(i) / Double(parts)
                result.append(Coordinate(latitude: a.latitude + (b.latitude - a.latitude) * t,
                                         longitude: a.longitude + (b.longitude - a.longitude) * t))
            }
        }
        return result
    }
}

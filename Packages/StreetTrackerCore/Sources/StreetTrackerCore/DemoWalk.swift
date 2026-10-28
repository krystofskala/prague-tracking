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
        // Named streets drawn point to point; skips squares drawn as areas
        // and long tunnels, which look like jumps across houses.
        // Sorted, so the walk is the same on every launch.
        let named = graph.segments.values.sorted { $0.id < $1.id }.filter { segment in
            segment.name != nil && segment.points.count >= 2
                && !(segment.name ?? "").localizedCaseInsensitiveContains("tunel")
                && zip(segment.points, segment.points.dropFirst()).allSatisfy { Geo.distance($0, $1) <= 60 }
        }
        guard var current = named.min(by: { nearest($0, start) < nearest($1, start) }) else { return [] }
        var used: Set<String> = [current.id]
        var points = Geo.distance(current.points.first!, start) <= Geo.distance(current.points.last!, start)
            ? current.points : current.points.reversed()
        var walked = length(points)
        while walked < maxMeters, let end = points.last {
            // The next segment closest to where we are; ways often cross
            // mid-way, so join at any of its points and walk to its
            // farther end.
            let next = named
                .filter { !used.contains($0.id) }
                .compactMap { segment -> (StreetSegment, Int, Double)? in
                    let distances = segment.points.map { Geo.distance($0, end) }
                    guard let i = distances.indices.min(by: { distances[$0] < distances[$1] }) else { return nil }
                    return (segment, i, distances[i])
                }
                .filter { $0.2 <= joinDistance }
                .min { $0.2 < $1.2 }
            guard let (segment, i, _) = next else { break }
            current = segment
            used.insert(segment.id)
            let forward = Array(segment.points[i...]), backward = Array(segment.points[...i].reversed())
            let more = length(forward) >= length(backward) ? forward : backward
            guard more.count >= 2 else { break }
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

import Foundation

/// One named street in one district: all its OSM ways together, which is
/// what a person means by "Karlova".
public struct StreetStatus: Sendable, Identifiable, Equatable {
    public var id: String { name + "|" + (district ?? "") }
    public let name: String
    public let district: String?
    public let segmentIDs: [String]
    public let lengthMeters: Double
    public let walkedMeters: Double

    public var fraction: Double { lengthMeters > 0 ? walkedMeters / lengthMeters : 0 }

    /// CityStrides counts a street done at 90 %, so a missed corner or a
    /// GPS gap doesn't keep it open forever; strict mode wants all of it.
    public func isDone(strict: Bool = false) -> Bool {
        fraction >= (strict ? 0.999 : StreetProgress.doneFraction)
    }
}

public enum StreetProgress {
    public static let doneFraction = 0.9

    /// Named streets only (unnamed paths and service roads aren't streets
    /// a person ticks off), longest first within the same name.
    public static func streets(graph: StreetGraph, passCounts: [String: Int]) -> [StreetStatus] {
        streets(graph: graph, walkedMeters: graph.segments.compactMapValues { segment in
            (passCounts[segment.id] ?? 0) > 0 ? segment.lengthMeters : nil
        })
    }

    /// With walked pieces (E4): `CoverageRebuild.walkedMeters`.
    public static func streets(graph: StreetGraph, walkedMeters: [String: Double]) -> [StreetStatus] {
        var groups: [String: [StreetSegment]] = [:]
        for segment in graph.segments.values {
            guard let name = segment.name, !name.isEmpty else { continue }
            groups[name + "|" + (segment.district ?? ""), default: []].append(segment)
        }
        return groups.values.map { segments in
            StreetStatus(
                name: segments[0].name!,
                district: segments[0].district,
                segmentIDs: segments.map(\.id).sorted(),
                lengthMeters: segments.reduce(0) { $0 + $1.lengthMeters },
                walkedMeters: segments.reduce(0) { $0 + (walkedMeters[$1.id] ?? 0) }
            )
        }
        .sorted { ($0.name, $0.district ?? "") < ($1.name, $1.district ?? "") }
    }

    /// Metres from `location` to the nearest point of the street.
    public static func distance(from location: Coordinate, to street: StreetStatus, graph: StreetGraph) -> Double {
        street.segmentIDs.compactMap { graph.segments[$0] }.flatMap(\.points)
            .map { Geo.distance($0, location) }
            .min() ?? .infinity
    }

    /// A walk through the nearest unfinished streets, nearest-neighbour
    /// order from `location`. Each stop is the street's point nearest to the
    /// previous stop. Not turn-by-turn: a plan to follow on the map.
    public static func plan(from location: Coordinate, streets: [StreetStatus], graph: StreetGraph,
                            count: Int = 6, strict: Bool = false) -> [(street: StreetStatus, point: Coordinate)] {
        var open = streets.filter { !$0.isDone(strict: strict) }
        var here = location
        var stops: [(StreetStatus, Coordinate)] = []
        while stops.count < count, !open.isEmpty {
            var best: (index: Int, point: Coordinate, distance: Double)?
            for (i, street) in open.enumerated() {
                for segment in street.segmentIDs.compactMap({ graph.segments[$0] }) where (segment.points.count) > 0 {
                    for point in segment.points {
                        let d = Geo.distance(point, here)
                        if d < (best?.distance ?? .infinity) { best = (i, point, d) }
                    }
                }
            }
            guard let best else { break }
            stops.append((open[best.index], best.point))
            here = best.point
            open.remove(at: best.index)
        }
        return stops
    }
}

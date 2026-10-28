import Foundation

public struct UnwalkedSuggestion: Sendable {
    public let segmentID: String
    public let name: String?
    public let distanceMeters: Double
    public let district: String?
}

/// Suggests where to walk next.
///
/// MVP simplification: this returns the nearest *unwalked segments*, not a
/// turn-by-turn route. Generating an actual efficient covering route (the
/// "Chinese Postman" / route inspection problem) needs an offline routing
/// graph with real shortest-path search (e.g. Dijkstra over the OSM graph),
/// which is a bigger v2 piece — see docs/ARCHITECTURE.md. A ranked nearby
/// list plus per-district completion is enough to plan a walk manually for
/// now: pick a low-coverage district, then head to its nearest unwalked
/// street.
public enum RouteSuggester {
    public static func nearestUnwalked(
        from location: Coordinate,
        graph: StreetGraph,
        coverage: CoverageStore,
        limit: Int = 20
    ) -> [UnwalkedSuggestion] {
        graph.segments.values
            .filter { coverage.passCount(for: $0.id) == 0 }
            .map { segment -> UnwalkedSuggestion in
                let nearestPoint = segment.points.min {
                    Geo.distance($0, location) < Geo.distance($1, location)
                } ?? segment.points[0]
                return UnwalkedSuggestion(
                    segmentID: segment.id,
                    name: segment.name,
                    distanceMeters: Geo.distance(nearestPoint, location),
                    district: segment.district
                )
            }
            .sorted { $0.distanceMeters < $1.distanceMeters }
            .filter(onePerStreet())
            .prefix(limit)
            .map { $0 }
    }

    /// A street is several OSM ways; list it once, at its nearest piece.
    private static func onePerStreet() -> (UnwalkedSuggestion) -> Bool {
        var seen: Set<String> = []
        return { suggestion in
            guard let name = suggestion.name else { return true }
            return seen.insert(name + "|" + (suggestion.district ?? "")).inserted
        }
    }

    /// The least-complete district that isn't already fully walked, if any.
    public static func leastCompleteDistrict(graph: StreetGraph, coverage: CoverageStore) -> String? {
        coverage.districtCoverage(graph: graph)
            .filter { $0.value < 1.0 }
            .min { $0.value < $1.value }?
            .key
    }
}

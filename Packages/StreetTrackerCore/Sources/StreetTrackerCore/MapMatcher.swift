import Foundation

public struct MatchResult: Sendable {
    public let segmentID: String
    public let distanceMeters: Double
    /// Where along the segment the fix lands, metres from its first point
    /// (E4: which piece of the street was walked).
    public var alongMeters: Double = 0
}

/// Snaps a raw GPS fix onto the nearest street segment.
///
/// MVP simplification: this is nearest-segment matching, not a full
/// Hidden-Markov-Model map matcher. It doesn't reason about direction of
/// travel or path continuity between fixes, so it can occasionally snap to
/// a parallel street (e.g. two close, roughly-parallel roads). That's an
/// acceptable trade for a first version; if it proves noisy in practice,
/// the natural upgrade is to weight candidates by consistency with the
/// previously matched segment / heading. See docs/ARCHITECTURE.md.
/// Immutable after init, so it can be built on a background thread and
/// handed to the main actor (the app builds it while loading street data).
public final class MapMatcher: @unchecked Sendable {
    private let graph: StreetGraph
    private let index: SpatialGridIndex
    public let maxMatchDistanceMeters: Double

    public init(graph: StreetGraph, maxMatchDistanceMeters: Double = 25) {
        self.graph = graph
        self.index = SpatialGridIndex(graph: graph)
        self.maxMatchDistanceMeters = maxMatchDistanceMeters
    }

    public func match(_ location: Coordinate) -> MatchResult? {
        candidates(location, limit: 1).first
    }

    /// Every street within `maxMatchDistanceMeters`, nearest first, each
    /// at its nearest point (for the HMM matcher).
    public func candidates(_ location: Coordinate, limit: Int = 8) -> [MatchResult] {
        let candidateIDs = index.candidateSegmentIDs(near: location)
        guard !candidateIDs.isEmpty else { return [] }

        let localPoint = Geo.toLocalMeters(location, origin: location) // always (0, 0)
        var results: [MatchResult] = []

        for id in candidateIDs {
            guard let segment = graph.segments[id] else { continue }
            var minDist = Double.greatestFiniteMagnitude
            var along = 0.0
            var walked = 0.0
            for i in 1..<segment.points.count {
                let a = Geo.toLocalMeters(segment.points[i - 1], origin: location)
                let b = Geo.toLocalMeters(segment.points[i], origin: location)
                let p = Geo.projection(p: localPoint, a: a, b: b)
                let d = (p.x * p.x + p.y * p.y).squareRoot()
                if d < minDist {
                    minDist = d
                    along = walked + ((p.x - a.x) * (p.x - a.x) + (p.y - a.y) * (p.y - a.y)).squareRoot()
                }
                walked += ((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)).squareRoot()
            }
            if minDist <= maxMatchDistanceMeters {
                results.append(MatchResult(segmentID: id, distanceMeters: minDist, alongMeters: along))
            }
        }
        // Ties by ID so the result doesn't depend on set order.
        results.sort { ($0.distanceMeters, $0.segmentID) < ($1.distanceMeters, $1.segmentID) }
        return Array(results.prefix(limit))
    }

    /// The nearest point on the nearest street, for drawing a missed piece
    /// of a walk by finger; nil away from streets.
    public func snap(_ location: Coordinate) -> Coordinate? {
        guard let match = match(location), let segment = graph.segments[match.segmentID] else { return nil }
        var best: (x: Double, y: Double) = (0, 0)
        var bestDistance = Double.greatestFiniteMagnitude
        for i in 1..<segment.points.count {
            let a = Geo.toLocalMeters(segment.points[i - 1], origin: location)
            let b = Geo.toLocalMeters(segment.points[i], origin: location)
            let p = Geo.projection(p: (0, 0), a: a, b: b)
            let d = (p.x * p.x + p.y * p.y).squareRoot()
            if d < bestDistance { bestDistance = d; best = p }
        }
        return Geo.fromLocalMeters(best, origin: location)
    }
}

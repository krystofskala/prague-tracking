import Foundation

/// Recomputes pass counts from every logged fix after the person edits a
/// walk (E3), with the same rules as live tracking (`CoverageStore`).
///
/// The CSV log only exists since 26. 10. 2026; passes from before can't be
/// recomputed. `legacy` keeps them: counts that the CSV can't explain,
/// taken once (`legacyCounts`) and added on top of every rebuild.
public enum CoverageRebuild {
    /// Points along a hand-drawn piece are matched this far apart.
    public static let drawnStep: Double = 5

    public static func passCounts(
        fixes: [Fix],
        excluded: [TimeRange] = [],
        drawn: [[Coordinate]] = [],
        manualSegments: Set<String> = [],
        legacy: [String: Int] = [:],
        graph: StreetGraph,
        matcher: MapMatcher,
        maxAccuracy: Double = WalkSplitter.maxAccuracy
    ) -> [String: Int] {
        let store = CoverageStore()
        let usable = fixes
            .filter { $0.walking && $0.accuracy >= 0 && $0.accuracy < maxAccuracy }
            .filter { fix in !excluded.contains { $0.contains(fix.time) } }
            .sorted { $0.time < $1.time }
        for fix in usable {
            guard let match = matcher.match(fix.coordinate) else { continue }
            let length = graph.segments[match.segmentID]?.lengthMeters ?? .infinity
            store.recordFix(on: match.segmentID, at: fix.time, segmentLengthMeters: length)
        }
        var counts = store.passCounts

        // A drawn piece walks each street it follows once.
        for piece in drawn {
            var hits: [String: Int] = [:]
            for point in densified(piece) {
                if let match = matcher.match(point) { hits[match.segmentID, default: 0] += 1 }
            }
            for (id, n) in hits {
                let length = graph.segments[id]?.lengthMeters ?? .infinity
                // Same idea as live tracking: one touch at a crossing isn't a walk.
                if n >= 2 || length < store.shortSegmentMeters { counts[id, default: 0] += 1 }
            }
        }
        for id in manualSegments where (counts[id] ?? 0) == 0 {
            counts[id] = 1
        }
        for (id, n) in legacy where n > 0 {
            counts[id, default: 0] += n
        }
        return counts
    }

    /// Passes in `current` that the CSV log doesn't explain (walked before
    /// the log existed). Take once, before the first edit, and keep.
    public static func legacyCounts(current: [String: Int], fromLog: [String: Int]) -> [String: Int] {
        current.reduce(into: [:]) { result, entry in
            let extra = entry.value - (fromLog[entry.key] ?? 0)
            if extra > 0 { result[entry.key] = extra }
        }
    }

    static func densified(_ piece: [Coordinate]) -> [Coordinate] {
        guard let first = piece.first else { return [] }
        var out = [first]
        for (a, b) in zip(piece, piece.dropFirst()) {
            let steps = max(1, Int((Geo.distance(a, b) / drawnStep).rounded(.up)))
            for i in 1...steps {
                let t = Double(i) / Double(steps)
                out.append(Coordinate(latitude: a.latitude + (b.latitude - a.latitude) * t,
                                      longitude: a.longitude + (b.longitude - a.longitude) * t))
            }
        }
        return out
    }
}

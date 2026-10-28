import Foundation

/// Map matching over a whole walk (E4), the hidden Markov model of Newson
/// & Krumm (2009) that OSRM and Valhalla use: each fix has a few candidate
/// streets nearby, and the best sequence is the one that is both close to
/// the fixes and makes sense as a walk: staying on a street or turning at
/// a crossing, not jumping to a parallel street and back.
///
/// Lighter than OSRM: routes are only looked up between streets that meet
/// (a shared node); anything else pays `jumpPenalty` on top of the straight
/// distance. Fixes come every second or few while walking, so consecutive
/// fixes are almost always on the same or a neighbouring street.
public final class HMMMatcher: @unchecked Sendable {
    /// GPS noise (σ of the distance to the street), metres.
    public static let sigma = 5.0
    /// How much the route may differ from the straight line, metres.
    public static let beta = 5.0
    public static let jumpPenalty = 40.0
    /// A longer pause between fixes starts a new chain.
    public static let chainGap: TimeInterval = 60

    private let graph: StreetGraph
    private let matcher: MapMatcher
    /// Where two streets meet: (along the first, along the second) for
    /// each shared node.
    private let junctions: [String: [String: [(Double, Double)]]]

    public init(graph: StreetGraph, matcher: MapMatcher) {
        self.graph = graph
        self.matcher = matcher
        var nodes: [Int64: [(segmentID: String, along: Double)]] = [:]
        for segment in graph.segments.values {
            var along = 0.0
            for (i, point) in segment.points.enumerated() {
                if i > 0 { along += Geo.distance(segment.points[i - 1], point) }
                nodes[Self.key(point), default: []].append((segment.id, along))
            }
        }
        var junctions: [String: [String: [(Double, Double)]]] = [:]
        for list in nodes.values where list.count > 1 {
            for x in list {
                for y in list where y.segmentID != x.segmentID {
                    junctions[x.segmentID, default: [:]][y.segmentID, default: []].append((x.along, y.along))
                }
            }
        }
        self.junctions = junctions
    }

    private static func key(_ c: Coordinate) -> Int64 {
        Int64((c.latitude * 1e6).rounded()) * 1_000_000_000 + Int64((c.longitude * 1e6).rounded())
    }

    /// Walking distance between two points on streets that are the same or
    /// meet; nil otherwise.
    func routeDistance(_ a: MatchResult, _ b: MatchResult) -> Double? {
        if a.segmentID == b.segmentID { return abs(a.alongMeters - b.alongMeters) }
        return junctions[a.segmentID]?[b.segmentID]?.map { abs(a.alongMeters - $0.0) + abs($0.1 - b.alongMeters) }.min()
    }

    /// The matched street for each fix (nil where no street is near).
    /// Fixes must be sorted by time.
    public func match(_ fixes: [Fix]) -> [MatchResult?] {
        var result = [MatchResult?](repeating: nil, count: fixes.count)
        var chain: [(index: Int, candidates: [MatchResult])] = []

        func finish() {
            for (i, match) in zip(chain.map(\.index), viterbi(chain.map(\.candidates), fixes: chain.map { fixes[$0.index] })) {
                result[i] = match
            }
            chain = []
        }

        for (i, fix) in fixes.enumerated() {
            let candidates = matcher.candidates(fix.coordinate)
            if candidates.isEmpty {
                finish()
                continue
            }
            if let last = chain.last, fix.time.timeIntervalSince(fixes[last.index].time) > Self.chainGap {
                finish()
            }
            chain.append((i, candidates))
        }
        finish()
        return result
    }

    private func viterbi(_ steps: [[MatchResult]], fixes: [Fix]) -> [MatchResult] {
        guard let first = steps.first else { return [] }
        var score = first.map { emission($0) }
        var back: [[Int]] = [Array(repeating: -1, count: first.count)]
        for t in 1..<max(steps.count, 1) {
            let straight = Geo.distance(fixes[t - 1].coordinate, fixes[t].coordinate)
            var next: [Double] = []
            var from: [Int] = []
            for b in steps[t] {
                var best = (-Double.infinity, 0)
                for (i, a) in steps[t - 1].enumerated() {
                    let route = routeDistance(a, b) ?? (straight + Self.jumpPenalty)
                    let s = score[i] - abs(route - straight) / Self.beta
                    if s > best.0 { best = (s, i) }
                }
                next.append(best.0 + emission(b))
                from.append(best.1)
            }
            score = next
            back.append(from)
        }
        var i = score.indices.max { score[$0] < score[$1] } ?? 0
        var path: [MatchResult] = []
        for t in stride(from: steps.count - 1, through: 0, by: -1) {
            path.append(steps[t][i])
            i = back[t][i]
        }
        return path.reversed()
    }

    private func emission(_ m: MatchResult) -> Double {
        -0.5 * (m.distanceMeters / Self.sigma) * (m.distanceMeters / Self.sigma)
    }
}

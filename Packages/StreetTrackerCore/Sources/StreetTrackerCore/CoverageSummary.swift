import Foundation

/// Coverage percentages kept up to date incrementally. `CoverageStore`'s
/// `coverageFraction` / `districtCoverage` walk all ~32k Prague segments on
/// every call; the app needs the numbers after each new pass, so totals are
/// computed once and only the walked lengths change.
public struct CoverageSummary: Sendable {
    public private(set) var totalLengthMeters: Double = 0
    public private(set) var walkedLengthMeters: Double = 0
    private var totalByDistrict: [String: Double] = [:]
    private var walkedByDistrict: [String: Double] = [:]
    private var walked: [String: Double] = [:]
    private let segments: [String: (length: Double, district: String)]

    public init(graph: StreetGraph, passCounts: [String: Int]) {
        segments = graph.segments.mapValues { ($0.lengthMeters, $0.district ?? "Unknown") }
        for (_, segment) in segments {
            totalLengthMeters += segment.length
            totalByDistrict[segment.district, default: 0] += segment.length
        }
        for (id, count) in passCounts where count > 0 {
            markWalked(id)
        }
    }

    /// With walked pieces (E4): `CoverageRebuild.walkedMeters`.
    public init(graph: StreetGraph, walkedMeters: [String: Double]) {
        self.init(graph: graph, passCounts: [:])
        for (id, meters) in walkedMeters {
            setWalked(id, meters: meters)
        }
    }

    /// Call when a segment gets its first pass; later passes don't change coverage.
    public mutating func markWalked(_ segmentID: String) {
        guard let segment = segments[segmentID] else { return }
        setWalked(segmentID, meters: segment.length)
    }

    /// Walked length of one segment changed (a new piece of it).
    public mutating func setWalked(_ segmentID: String, meters: Double) {
        guard let segment = segments[segmentID] else { return }
        let delta = min(meters, segment.length) - (walked[segmentID] ?? 0)
        guard delta != 0 else { return }
        walked[segmentID] = min(meters, segment.length)
        walkedLengthMeters += delta
        walkedByDistrict[segment.district, default: 0] += delta
    }

    /// Fraction (0...1) of total street length walked at least once.
    public var fraction: Double {
        totalLengthMeters > 0 ? walkedLengthMeters / totalLengthMeters : 0
    }

    /// Same as `CoverageStore.districtCoverage`.
    public var districtFractions: [String: Double] {
        var result: [String: Double] = [:]
        for (district, total) in totalByDistrict where total > 0 {
            result[district] = (walkedByDistrict[district] ?? 0) / total
        }
        return result
    }
}

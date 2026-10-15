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
    private var walkedIDs: Set<String> = []
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

    /// Call when a segment gets its first pass; later passes don't change coverage.
    public mutating func markWalked(_ segmentID: String) {
        guard let segment = segments[segmentID], walkedIDs.insert(segmentID).inserted else { return }
        walkedLengthMeters += segment.length
        walkedByDistrict[segment.district, default: 0] += segment.length
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

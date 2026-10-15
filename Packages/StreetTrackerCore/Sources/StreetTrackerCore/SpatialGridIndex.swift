import Foundation

/// Uniform grid over lat/lon used to avoid scanning every segment on each
/// GPS fix. Prague's full walkable network is tens of thousands of ways;
/// a linear scan per location update would not keep up in real time.
final class SpatialGridIndex {
    private struct GridKey: Hashable {
        let x: Int
        let y: Int
    }

    private let cellSizeDegrees: Double
    private var cells: [GridKey: Set<String>] = [:]

    /// ~0.002 degrees is roughly 150-220m at Prague's latitude — small
    /// enough that a 3x3 cell search comfortably covers GPS noise.
    init(graph: StreetGraph, cellSizeDegrees: Double = 0.002) {
        self.cellSizeDegrees = cellSizeDegrees
        for (id, segment) in graph.segments {
            for point in segment.points {
                cells[Self.key(for: point, cellSize: cellSizeDegrees), default: []].insert(id)
            }
            // Also every cell an edge passes through: OSM leaves no nodes along
            // straight stretches (some Prague edges are 700 m+), and a fix in
            // the middle of one would otherwise find no candidates at all.
            for (a, b) in zip(segment.points, segment.points.dropFirst()) {
                let steps = Int(max(abs(b.latitude - a.latitude), abs(b.longitude - a.longitude)) / (cellSizeDegrees / 2))
                guard steps > 1 else { continue }
                for step in 1..<steps {
                    let t = Double(step) / Double(steps)
                    let point = Coordinate(
                        latitude: a.latitude + (b.latitude - a.latitude) * t,
                        longitude: a.longitude + (b.longitude - a.longitude) * t
                    )
                    cells[Self.key(for: point, cellSize: cellSizeDegrees), default: []].insert(id)
                }
            }
        }
    }

    private static func key(for coord: Coordinate, cellSize: Double) -> GridKey {
        GridKey(x: Int(floor(coord.longitude / cellSize)), y: Int(floor(coord.latitude / cellSize)))
    }

    func candidateSegmentIDs(near coord: Coordinate, radiusCells: Int = 1) -> Set<String> {
        let center = Self.key(for: coord, cellSize: cellSizeDegrees)
        var result: Set<String> = []
        for dx in -radiusCells...radiusCells {
            for dy in -radiusCells...radiusCells {
                let key = GridKey(x: center.x + dx, y: center.y + dy)
                if let ids = cells[key] {
                    result.formUnion(ids)
                }
            }
        }
        return result
    }
}

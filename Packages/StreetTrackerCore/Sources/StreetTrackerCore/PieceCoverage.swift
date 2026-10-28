import Foundation

/// Which parts of each street were walked (E4). A segment is a whole OSM
/// way, sometimes hundreds of metres long; touching one end used to count
/// all of it. Here every segment is cut into pieces of about
/// `pieceMeters` and only the pieces actually walked count, like
/// CityStrides counts a street's nodes.
///
/// Segments with passes but no pieces (walked before the CSV log, marked
/// by hand) count whole; see `walkedMeters(of:passCount:)`.
public struct PieceCoverage: Codable, Sendable, Equatable {
    public static let pieceMeters = 20.0
    /// Two fixes on the same street this close in time walked everything
    /// between them.
    public static let fillWindow: TimeInterval = 60
    /// Faster than this between two fixes isn't walking the street between them.
    public static let maxFillSpeed = 4.0

    public private(set) var walked: [String: Set<Int>]
    /// Segments that count whole (hand-marked, hand-drawn over, pre-log).
    public private(set) var whole: Set<String>

    public init(walked: [String: Set<Int>] = [:], whole: Set<String> = []) {
        self.walked = walked
        self.whole = whole
    }

    public static func pieceCount(lengthMeters: Double) -> Int {
        max(1, Int((lengthMeters / pieceMeters).rounded(.up)))
    }

    static func index(along: Double, segment: StreetSegment) -> Int {
        let length = Geo.polylineLength(segment.points)
        let count = pieceCount(lengthMeters: segment.lengthMeters)
        guard length > 0 else { return 0 }
        return min(count - 1, max(0, Int(along / length * Double(count))))
    }

    /// Marks the pieces between two positions along `segment` (metres from
    /// its first point). Returns whether a new piece was added.
    @discardableResult
    public mutating func mark(_ segment: StreetSegment, from: Double, to: Double) -> Bool {
        guard !whole.contains(segment.id) else { return false }
        let a = Self.index(along: min(from, to), segment: segment)
        let b = Self.index(along: max(from, to), segment: segment)
        let before = walked[segment.id]?.count ?? 0
        walked[segment.id, default: []].formUnion(a...b)
        return walked[segment.id]!.count > before
    }

    public mutating func markWhole(_ segmentID: String) {
        whole.insert(segmentID)
        walked[segmentID] = nil
    }

    public mutating func merge(_ other: PieceCoverage) {
        whole.formUnion(other.whole)
        for (id, pieces) in other.walked where !whole.contains(id) {
            walked[id, default: []].formUnion(pieces)
        }
        for id in whole { walked[id] = nil }
    }

    public func fraction(of segment: StreetSegment) -> Double {
        if whole.contains(segment.id) { return 1 }
        guard let pieces = walked[segment.id] else { return 0 }
        return Double(pieces.count) / Double(Self.pieceCount(lengthMeters: segment.lengthMeters))
    }

    /// Walked length of every segment that has any.
    public func walkedMeters(graph: StreetGraph) -> [String: Double] {
        var result: [String: Double] = [:]
        for id in whole {
            if let segment = graph.segments[id] { result[id] = segment.lengthMeters }
        }
        for id in walked.keys {
            if let segment = graph.segments[id] { result[id] = fraction(of: segment) * segment.lengthMeters }
        }
        return result
    }

    /// Runs of walked pieces as lines, for drawing only the walked part.
    /// Nil when the segment counts whole (draw all of it).
    public func walkedLines(of segment: StreetSegment) -> [[Coordinate]]? {
        if whole.contains(segment.id) { return nil }
        guard let pieces = walked[segment.id], !pieces.isEmpty else { return [] }
        let count = Self.pieceCount(lengthMeters: segment.lengthMeters)
        if pieces.count == count { return nil }
        let length = Geo.polylineLength(segment.points)
        let step = length / Double(count)
        var lines: [[Coordinate]] = []
        var start: Int?
        for i in 0...count {
            if i < count, pieces.contains(i) {
                if start == nil { start = i }
            } else if let s = start {
                lines.append(Geo.subPolyline(segment.points, from: Double(s) * step, to: Double(i) * step))
                start = nil
            }
        }
        return lines
    }
}

/// Turns matched fixes into walked pieces, filling the street between two
/// fixes on it that are close in time.
public struct PieceTracker: Sendable {
    private var last: (segmentID: String, along: Double, time: Date)?

    public init() {}

    /// Returns whether a new piece was walked.
    public mutating func record(_ match: MatchResult, at time: Date, graph: StreetGraph, into coverage: inout PieceCoverage) -> Bool {
        guard let segment = graph.segments[match.segmentID] else { return false }
        var from = match.alongMeters
        if let last, last.segmentID == match.segmentID {
            let seconds = time.timeIntervalSince(last.time)
            let meters = abs(match.alongMeters - last.along)
            if seconds >= 0, seconds <= PieceCoverage.fillWindow, meters <= PieceCoverage.maxFillSpeed * seconds + 25 {
                from = last.along
            }
        }
        last = (match.segmentID, match.alongMeters, time)
        return coverage.mark(segment, from: from, to: match.alongMeters)
    }
}

extension Geo {
    /// The part of a polyline between two distances along it.
    public static func subPolyline(_ points: [Coordinate], from: Double, to: Double) -> [Coordinate] {
        guard points.count >= 2, to > from else { return [] }
        var out: [Coordinate] = []
        var walked = 0.0
        for (a, b) in zip(points, points.dropFirst()) {
            let d = distance(a, b)
            let start = walked, end = walked + d
            walked = end
            guard end >= from, start <= to, d > 0 else { continue }
            func at(_ m: Double) -> Coordinate {
                let t = max(0, min(1, (m - start) / d))
                return Coordinate(latitude: a.latitude + (b.latitude - a.latitude) * t,
                                  longitude: a.longitude + (b.longitude - a.longitude) * t)
            }
            if out.isEmpty { out.append(at(max(from, start))) }
            out.append(at(min(to, end)))
        }
        return out
    }
}

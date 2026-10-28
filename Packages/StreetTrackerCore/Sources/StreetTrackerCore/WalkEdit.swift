import Foundation

/// A span of time cut out of a walk (a tram ride the GPS took for walking).
public struct TimeRange: Codable, Sendable, Equatable {
    public var from: Date
    public var to: Date

    public init(from: Date, to: Date) {
        self.from = min(from, to)
        self.to = max(from, to)
    }

    public func contains(_ time: Date) -> Bool { time >= from && time <= to }
}

/// The person's changes to one walk (E3). The CSV with the original fixes
/// is never touched, so every edit can be undone by removing it here.
public struct WalkEdit: Codable, Sendable, Equatable {
    public var trimStart: Date?
    public var trimEnd: Date?
    public var removed: [TimeRange]
    /// Pieces drawn by finger where the GPS missed the walk, already
    /// snapped to streets by the app.
    public var drawn: [[Coordinate]]

    public init(trimStart: Date? = nil, trimEnd: Date? = nil, removed: [TimeRange] = [], drawn: [[Coordinate]] = []) {
        self.trimStart = trimStart
        self.trimEnd = trimEnd
        self.removed = removed
        self.drawn = drawn
    }

    public var isEmpty: Bool { trimStart == nil && trimEnd == nil && removed.isEmpty && drawn.isEmpty }

    /// False for fixes trimmed off or inside a removed piece.
    public func keeps(_ time: Date) -> Bool {
        if let trimStart, time < trimStart { return false }
        if let trimEnd, time > trimEnd { return false }
        return !removed.contains { $0.contains(time) }
    }

    /// Everything this edit takes out of `walk`, for recomputing coverage
    /// from all fixes: trims become ranges reaching to the walk's ends.
    public func excludedRanges(of walk: Walk) -> [TimeRange] {
        var ranges = removed
        if let trimStart, trimStart > walk.start { ranges.append(TimeRange(from: walk.start, to: trimStart.addingTimeInterval(-0.001))) }
        if let trimEnd, trimEnd < walk.end { ranges.append(TimeRange(from: trimEnd.addingTimeInterval(0.001), to: walk.end)) }
        return ranges
    }
}

extension Walk {
    /// The walk as the person edited it, or nil when nothing is left. A
    /// removed piece in the middle splits its segment in two, so the gap
    /// isn't drawn as a straight line.
    public func applying(_ edit: WalkEdit?) -> Walk? {
        guard let edit, !edit.isEmpty else { return self }
        var pieces: [[Fix]] = []
        for segment in segments {
            var current: [Fix] = []
            for fix in segment {
                if edit.keeps(fix.time) {
                    current.append(fix)
                } else if !current.isEmpty {
                    pieces.append(current)
                    current = []
                }
            }
            if !current.isEmpty { pieces.append(current) }
        }
        let drawn = edit.drawn.filter { $0.count >= 2 }
        guard !pieces.isEmpty else { return nil }
        return Walk(id: id, segments: pieces, drawn: self.drawn + drawn)
    }
}

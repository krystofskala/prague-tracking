import Foundation

/// A whole walk drawn by hand afterwards (the phone was flat, the GPS was
/// off): the drawn strokes become fixes at walking pace from `start`, so
/// the walk joins the list, the coverage and the stats like a recorded one.
public enum DrawnWalk {
    /// Metres between generated fixes.
    public static let step: Double = 4
    /// Walking pace, m/s.
    public static let speed: Double = 1.3

    /// Strokes in the order they were drawn; the time between two strokes
    /// is the straight walk from one end to the next start.
    public static func fixes(strokes: [[Coordinate]], start: Date) -> [Fix] {
        var fixes: [Fix] = []
        var time = start
        var previous: Coordinate?
        for stroke in strokes where stroke.count >= 2 {
            for point in densified(stroke) {
                if let previous { time = time.addingTimeInterval(Geo.distance(previous, point) / speed) }
                fixes.append(Fix(time: time, coordinate: point, accuracy: 5, speed: speed, walking: true))
                previous = point
            }
        }
        return fixes
    }

    public static func length(of strokes: [[Coordinate]]) -> Double {
        strokes.reduce(0) { $0 + Geo.polylineLength($1) }
    }

    static func densified(_ line: [Coordinate]) -> [Coordinate] {
        var out = [line[0]]
        for (a, b) in zip(line, line.dropFirst()) {
            let steps = max(1, Int((Geo.distance(a, b) / step).rounded(.up)))
            for i in 1...steps {
                let t = Double(i) / Double(steps)
                out.append(Coordinate(latitude: a.latitude + (b.latitude - a.latitude) * t,
                                      longitude: a.longitude + (b.longitude - a.longitude) * t))
            }
        }
        return out
    }
}

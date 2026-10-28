import Foundation

/// One GPS fix as written to the daily CSV (`TrackLog` in the app).
public struct Fix: Sendable, Equatable {
    public var time: Date
    public var coordinate: Coordinate
    /// Metres; negative when unknown.
    public var accuracy: Double
    /// m/s; nil when the GPS didn't know.
    public var speed: Double?
    public var walking: Bool
    public var street: String?
    public var district: String?

    public init(time: Date, coordinate: Coordinate, accuracy: Double = 5, speed: Double? = nil,
                walking: Bool = true, street: String? = nil, district: String? = nil) {
        self.time = time
        self.coordinate = coordinate
        self.accuracy = accuracy
        self.speed = speed
        self.walking = walking
        self.street = street
        self.district = district
    }
}

/// Reads the daily CSV: `cas,lat,lon,presnost_m,rychlost_ms,chuze,ulice,ctvrt`.
public enum TrackCSV {
    public static let header = "cas,lat,lon,presnost_m,rychlost_ms,chuze,ulice,ctvrt"

    public static func parse(_ text: String) -> [Fix] {
        let time = ISO8601DateFormatter()
        time.formatOptions = [.withInternetDateTime]
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            let f = fields(String(line))
            guard f.count >= 6, let date = time.date(from: f[0]),
                  let lat = Double(f[1]), let lon = Double(f[2]) else { return nil }
            return Fix(
                time: date,
                coordinate: Coordinate(latitude: lat, longitude: lon),
                accuracy: Double(f[3]) ?? -1,
                speed: Double(f[4]),
                walking: f[5] == "1",
                street: f.count > 6 && !f[6].isEmpty ? f[6] : nil,
                district: f.count > 7 && !f[7].isEmpty ? f[7] : nil
            )
        }
    }

    public static func line(_ fix: Fix, formatter: ISO8601DateFormatter) -> String {
        [
            formatter.string(from: fix.time),
            String(format: "%.6f", fix.coordinate.latitude),
            String(format: "%.6f", fix.coordinate.longitude),
            String(format: "%.0f", fix.accuracy),
            fix.speed.map { String(format: "%.1f", $0) } ?? "",
            fix.walking ? "1" : "0",
            quoted(fix.street),
            quoted(fix.district),
        ].joined(separator: ",")
    }

    static func quoted(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "" }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Splits one CSV line, honouring "quoted, fields" with "" escapes.
    static func fields(_ line: String) -> [String] {
        var result: [String] = []
        var field = ""
        var inQuotes = false
        var chars = line.makeIterator()
        while let c = chars.next() {
            if inQuotes {
                if c == "\"" {
                    // Peek: a doubled quote is a literal quote.
                    if let n = chars.next() {
                        if n == "\"" { field.append("\"") } else {
                            inQuotes = false
                            if n == "," { result.append(field); field = "" } else { field.append(n) }
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else if c == "\"" {
                inQuotes = true
            } else if c == "," {
                result.append(field)
                field = ""
            } else {
                field.append(c)
            }
        }
        result.append(field)
        return result
    }
}

/// A walk: walking fixes with no pause longer than `WalkSplitter.pause`.
/// Shorter GPS gaps split it into segments (GPX `<trkseg>`), so a gap is
/// never drawn as a straight line through houses.
public struct Walk: Sendable, Equatable {
    /// `RRRR-MM-DD-HHMM` of the start in local time; the note's file name.
    public let id: String
    public let segments: [[Fix]]
    /// Pieces drawn by hand (`WalkEdit.drawn`); no times, so no fixes.
    public let drawn: [[Coordinate]]

    public init(id: String, segments: [[Fix]], drawn: [[Coordinate]] = []) {
        self.id = id
        self.segments = segments
        self.drawn = drawn
    }

    public var start: Date { segments.first!.first!.time }
    public var end: Date { segments.last!.last!.time }
    public var fixes: [Fix] { segments.flatMap { $0 } }

    public var distanceMeters: Double {
        let recorded = segments.reduce(0) { total, segment in
            total + zip(segment, segment.dropFirst()).reduce(0) { $0 + Geo.distance($1.0.coordinate, $1.1.coordinate) }
        }
        return drawn.reduce(recorded) { total, piece in
            total + zip(piece, piece.dropFirst()).reduce(0) { $0 + Geo.distance($1.0, $1.1) }
        }
    }

    /// Streets in the order first walked.
    public var streets: [String] { ordered(fixes.compactMap(\.street)) }
    public var districts: [String] { ordered(fixes.compactMap(\.district)) }

    private func ordered(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }
}

public enum WalkSplitter {
    /// Longer than this without a walking fix ends the walk.
    public static let pause: TimeInterval = 5 * 60
    /// Longer than this without a fix starts a new segment.
    public static let gap: TimeInterval = 60
    /// Shorter walks are noise (a few steps to the tram).
    public static let minDistance: Double = 200
    public static let maxAccuracy: Double = 50

    public static func walks(from fixes: [Fix], timeZone: TimeZone = .current) -> [Walk] {
        let usable = fixes
            .filter { $0.walking && $0.accuracy >= 0 && $0.accuracy < maxAccuracy }
            .sorted { $0.time < $1.time }
        var walks: [[[Fix]]] = []
        for fix in usable {
            guard let last = walks.last?.last?.last else {
                walks.append([[fix]])
                continue
            }
            let silence = fix.time.timeIntervalSince(last.time)
            if silence > pause {
                walks.append([[fix]])
            } else if silence > gap {
                walks[walks.count - 1].append([fix])
            } else {
                walks[walks.count - 1][walks[walks.count - 1].count - 1].append(fix)
            }
        }
        let idFormatter = DateFormatter()
        idFormatter.locale = Locale(identifier: "en_US_POSIX")
        idFormatter.timeZone = timeZone
        idFormatter.dateFormat = "yyyy-MM-dd-HHmm"
        return walks
            .map { Walk(id: idFormatter.string(from: $0[0][0].time), segments: $0) }
            .filter { $0.distanceMeters >= minDistance }
    }
}

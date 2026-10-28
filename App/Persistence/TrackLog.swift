import Foundation
import CoreLocation

/// Raw walk log: every GPS fix with its exact time and accuracy (nothing is
/// filtered out here), one CSV file per day in Documents/trasy/, plus a
/// daily event log (mode switches, relaunches, errors) to explain gaps. Pass counts alone can't say *when* a street
/// was walked; this file keeps the full route so anything can be
/// recomputed later. Documents is visible in the Files app (see
/// UIFileSharingEnabled in project.yml). Like CoveragePersistence, it never
/// leaves the device.
final class TrackLog {
    static let header = "cas,lat,lon,presnost_m,rychlost_ms,chuze,ulice,ctvrt\n"

    private let dir: URL
    private let dayFormatter: DateFormatter
    private let timeFormatter = ISO8601DateFormatter()

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        dir = documents.appendingPathComponent("trasy", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd"
        // Local time with offset, e.g. 2026-10-26T19:42:07+01:00.
        timeFormatter.timeZone = .current
        timeFormatter.formatOptions = [.withInternetDateTime]
    }

    func append(_ location: CLLocation, isWalking: Bool, street: StreetInfo?) {
        let fields = [
            timeFormatter.string(from: location.timestamp),
            String(format: "%.6f", location.coordinate.latitude),
            String(format: "%.6f", location.coordinate.longitude),
            String(format: "%.0f", location.horizontalAccuracy),
            location.speed >= 0 ? String(format: "%.1f", location.speed) : "",
            isWalking ? "1" : "0",
            Self.csvField(street?.name),
            Self.csvField(street?.district),
        ]
        let line = fields.joined(separator: ",") + "\n"
        append(line, to: "\(dayFormatter.string(from: location.timestamp)).csv", header: Self.header)
    }

    static let eventHeader = "cas,udalost,detail\n"

    func appendEvent(_ kind: String, _ detail: String, at time: Date = Date()) {
        let line = [timeFormatter.string(from: time), kind, Self.csvField(detail)].joined(separator: ",") + "\n"
        append(line, to: "udalosti-\(dayFormatter.string(from: time)).csv", header: Self.eventHeader)
    }

    /// Today's fixes accurate enough to draw, for the route on the map.
    func todaysRoute(maxAccuracy: Double) -> [CLLocationCoordinate2D] {
        let url = dir.appendingPathComponent("\(dayFormatter.string(from: Date())).csv")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").dropFirst().compactMap { line in
            // cas,lat,lon,presnost_m,... — the quoted street fields come last.
            let fields = line.split(separator: ",", maxSplits: 4, omittingEmptySubsequences: false)
            guard fields.count >= 4,
                  let lat = Double(fields[1]), let lon = Double(fields[2]),
                  let accuracy = Double(fields[3]), accuracy >= 0, accuracy < maxAccuracy
            else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
    }

    private func append(_ line: String, to name: String, header: String) {
        let url = dir.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? Data(header.utf8).write(to: url, options: .atomic)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        handle.write(Data(line.utf8))
    }

    struct StreetInfo {
        let name: String?
        let district: String?
    }

    private static func csvField(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "" }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

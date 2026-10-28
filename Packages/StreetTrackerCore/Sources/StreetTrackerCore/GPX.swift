import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// GPX 1.1 export of a walk and import of tracks from other apps (Strava,
/// Garmin, Open GPX Tracker...).
public enum GPX {
    public static func write(_ walk: Walk, name: String) -> String {
        let time = ISO8601DateFormatter()
        var out = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Prague Streets" xmlns="http://www.topografix.com/GPX/1/1">
          <metadata><name>\(escape(name))</name><time>\(time.string(from: walk.start))</time></metadata>
          <trk>
            <name>\(escape(name))</name>
            <type>walking</type>

        """
        for segment in walk.segments {
            out += "    <trkseg>\n"
            for fix in segment {
                out += String(format: "      <trkpt lat=\"%.6f\" lon=\"%.6f\">", fix.coordinate.latitude, fix.coordinate.longitude)
                out += "<time>\(time.string(from: fix.time))</time></trkpt>\n"
            }
            out += "    </trkseg>\n"
        }
        out += "  </trk>\n</gpx>\n"
        return out
    }

    /// Track segments of every `<trk>` (and `<rte>` points as one segment).
    /// Points without a time get none; the caller decides what to do.
    public static func read(_ data: Data) -> [[(Coordinate, Date?)]] {
        let reader = Reader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        parser.parse()
        reader.closeSegment()
        return reader.segments
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private final class Reader: NSObject, XMLParserDelegate {
        var segments: [[(Coordinate, Date?)]] = []
        private var current: [(Coordinate, Date?)] = []
        private var point: Coordinate?
        private var pointTime: Date?
        private var text = ""
        private let iso = ISO8601DateFormatter()
        private let isoFraction: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f
        }()

        func closeSegment() {
            if !current.isEmpty { segments.append(current) }
            current = []
        }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            text = ""
            switch name {
            case "trkseg", "rte": closeSegment()
            case "trkpt", "rtept":
                if let lat = attributes["lat"].flatMap(Double.init), let lon = attributes["lon"].flatMap(Double.init) {
                    point = Coordinate(latitude: lat, longitude: lon)
                    pointTime = nil
                }
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            switch name {
            case "time" where point != nil:
                let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                pointTime = iso.date(from: t) ?? isoFraction.date(from: t)
            case "trkpt", "rtept":
                if let point { current.append((point, pointTime)) }
                point = nil
            case "trkseg", "rte": closeSegment()
            default: break
            }
        }
    }
}

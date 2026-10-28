import Foundation

/// What the person adds to a walk in the app (E3): a name, tags, a colour.
public struct WalkMeta: Codable, Sendable, Equatable {
    public var title: String?
    public var tags: [String]
    /// Hex like `#2fdacc`.
    public var color: String?

    public init(title: String? = nil, tags: [String] = [], color: String? = nil) {
        self.title = title
        self.tags = tags
        self.color = color
    }
}

/// The Obsidian note for one walk: frontmatter for Bases/Dataview, a map
/// of the GPX next to it, the streets walked. Anything the person writes
/// under `ownNotesHeading` survives every rewrite.
public enum WalkNote {
    public static let ownNotesHeading = "## Moje poznámky"

    public static func markdown(_ walk: Walk, meta: WalkMeta = WalkMeta(), newStreets: Int? = nil,
                                timeZone: TimeZone = .current) -> String {
        let day = formatter("yyyy-MM-dd", timeZone)
        let clock = formatter("HH:mm", timeZone)
        let human = formatter("d. M. yyyy", timeZone)
        let km = walk.distanceMeters / 1000
        let title = meta.title ?? "Procházka \(human.string(from: walk.start)) \(clock.string(from: walk.start))"
        let tags = ["prochazka"] + meta.tags.map { $0.replacingOccurrences(of: " ", with: "-") }

        var out = "---\n"
        out += "created: \(day.string(from: walk.start))\n"
        out += "type: prochazka\n"
        out += "nazev: \(yaml(title))\n"
        out += "datum: \(day.string(from: walk.start))\n"
        out += "od: \"\(clock.string(from: walk.start))\"\n"
        out += "do: \"\(clock.string(from: walk.end))\"\n"
        out += "delka_km: \(String(format: "%.2f", km))\n"
        out += "minuty: \(Int((walk.end.timeIntervalSince(walk.start) / 60).rounded()))\n"
        out += "ulice: \(walk.streets.count)\n"
        if let newStreets { out += "nove_ulice: \(newStreets)\n" }
        out += "ctvrti: [\(walk.districts.map(yaml).joined(separator: ", "))]\n"
        out += "tags: [\(tags.map(yaml).joined(separator: ", "))]\n"
        if let color = meta.color { out += "barva: \(yaml(color))\n" }
        out += "gpx: \"[[\(walk.id).gpx]]\"\n"
        out += "source: Prague Streets (iPhone)\n"
        out += "---\n\n"
        out += "# \(title)\n\n"
        let districts = walk.districts.isEmpty ? "" : " · " + walk.districts.joined(separator: ", ")
        out += "\(String(format: "%.1f", km).replacingOccurrences(of: ".", with: ",")) km · "
        out += "\(clock.string(from: walk.start))–\(clock.string(from: walk.end)) · \(walk.streets.count) ulic\(districts)\n\n"
        out += "```leaflet\nid: \(walk.id)\nheight: 400px\ngpx: [[\(walk.id).gpx]]\n```\n\n"
        if !walk.streets.isEmpty {
            out += "## Ulice\n\n" + walk.streets.map { "- \($0)" }.joined(separator: "\n") + "\n\n"
        }
        out += ownNotesHeading + "\n\n"
        return out
    }

    /// Keeps the person's own part of an existing note.
    public static func merge(generated: String, existing: String?) -> String {
        guard let existing, let range = existing.range(of: ownNotesHeading) else { return generated }
        let own = existing[range.upperBound...]
        guard let mine = generated.range(of: ownNotesHeading) else { return generated }
        return String(generated[..<mine.upperBound]) + own
    }

    private static func formatter(_ format: String, _ timeZone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = format
        return f
    }

    private static func yaml(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

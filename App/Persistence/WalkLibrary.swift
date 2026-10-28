import Foundation
import StreetTrackerCore

/// All walks from the daily CSVs (and imported GPX), anywhere in the world,
/// plus what the person added to them (name, tags, colour). Local only.
final class WalkLibrary: @unchecked Sendable {
    let trasyDir: URL
    let importDir: URL
    private let metaURL: URL

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        trasyDir = documents.appendingPathComponent("trasy", isDirectory: true)
        importDir = trasyDir.appendingPathComponent("import", isDirectory: true)
        try? FileManager.default.createDirectory(at: importDir, withIntermediateDirectories: true)
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        metaURL = support.appendingPathComponent("walk-meta.json")
    }

    /// Fix CSVs: `RRRR-MM-DD.csv` and everything in `import/`.
    var csvFiles: [URL] {
        let fm = FileManager.default
        let daily = (try? fm.contentsOfDirectory(at: trasyDir, includingPropertiesForKeys: nil)) ?? []
        let imported = (try? fm.contentsOfDirectory(at: importDir, includingPropertiesForKeys: nil)) ?? []
        return (daily + imported).filter {
            $0.pathExtension == "csv" && !$0.lastPathComponent.hasPrefix("udalosti-")
        }
    }

    /// Newest first. Reads every file; call off the main thread.
    func loadWalks(changedSince: Date? = nil) -> [Walk] {
        let files = csvFiles.filter { url in
            guard let changedSince else { return true }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return (modified ?? .distantFuture) >= changedSince
        }
        let fixes = files.flatMap { url -> [Fix] in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
            return TrackCSV.parse(text)
        }
        return WalkSplitter.walks(from: fixes).sorted { $0.start > $1.start }
    }

    func loadMeta() -> [String: WalkMeta] {
        guard let data = try? Data(contentsOf: metaURL) else { return [:] }
        return (try? JSONDecoder().decode([String: WalkMeta].self, from: data)) ?? [:]
    }

    func saveMeta(_ meta: [String: WalkMeta]) {
        guard let data = try? JSONEncoder().encode(meta) else { return }
        try? data.write(to: metaURL, options: .atomic)
    }

    var metaFile: URL { metaURL }

    /// Writes an imported GPX track as its own CSV so it joins the walks.
    /// Points without a time get one 3 s after the previous (or `fallback`).
    @discardableResult
    func importGPX(_ data: Data, name: String, fallback: Date) -> [Fix] {
        var fixes: [Fix] = []
        var lastTime = fallback
        for segment in GPX.read(data) {
            for (coord, time) in segment {
                let t = time ?? lastTime.addingTimeInterval(3)
                lastTime = t
                fixes.append(Fix(time: t, coordinate: coord, accuracy: 5, walking: true))
            }
        }
        guard !fixes.isEmpty else { return [] }
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        let body = fixes.map { TrackCSV.line($0, formatter: formatter) }.joined(separator: "\n")
        let safe = name.replacingOccurrences(of: "/", with: "-")
        let url = importDir.appendingPathComponent((safe as NSString).deletingPathExtension + ".csv")
        try? Data((TrackCSV.header + "\n" + body + "\n").utf8).write(to: url, options: .atomic)
        return fixes
    }
}

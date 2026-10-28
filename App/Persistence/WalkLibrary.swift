import Foundation
import StreetTrackerCore

/// All walks from the daily CSVs (and imported GPX), anywhere in the world,
/// plus what the person added to them (name, tags, colour). Local only.
final class WalkLibrary: @unchecked Sendable {
    let trasyDir: URL
    let importDir: URL
    private let metaURL: URL
    let manualFile: URL
    let legacyFile: URL
    let goalsFile: URL
    let piecesFile: URL

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        trasyDir = documents.appendingPathComponent("trasy", isDirectory: true)
        importDir = trasyDir.appendingPathComponent("import", isDirectory: true)
        try? FileManager.default.createDirectory(at: importDir, withIntermediateDirectories: true)
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        metaURL = support.appendingPathComponent("walk-meta.json")
        manualFile = support.appendingPathComponent("rucne-prosle-ulice.json")
        legacyFile = support.appendingPathComponent("pokryti-pred-csv.json")
        goalsFile = support.appendingPathComponent("vyzvy.json")
        piecesFile = support.appendingPathComponent("kusy-ulic.json")
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
        return WalkSplitter.walks(from: fixes(in: files)).sorted { $0.start > $1.start }
    }

    /// Every logged fix, for recomputing coverage. Call off the main thread.
    func loadFixes() -> [Fix] { fixes(in: csvFiles) }

    private func fixes(in files: [URL]) -> [Fix] {
        files.flatMap { url -> [Fix] in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
            return TrackCSV.parse(text)
        }
    }

    /// Streets marked "tuhle jsem prošel" by hand (segment IDs).
    func loadManualStreets() -> Set<String> {
        guard let data = try? Data(contentsOf: manualFile) else { return [] }
        return (try? JSONDecoder().decode(Set<String>.self, from: data)) ?? []
    }

    func saveManualStreets(_ ids: Set<String>) {
        guard let data = try? JSONEncoder().encode(ids.sorted()) else { return }
        try? data.write(to: manualFile, options: .atomic)
    }

    /// Passes the CSV log can't explain (walked before it existed); taken
    /// once at the first recompute. Nil until then.
    func loadLegacy() -> [String: Int]? {
        guard let data = try? Data(contentsOf: legacyFile) else { return nil }
        return try? JSONDecoder().decode([String: Int].self, from: data)
    }

    func saveLegacy(_ counts: [String: Int]) {
        guard let data = try? JSONEncoder().encode(counts) else { return }
        try? data.write(to: legacyFile, options: .atomic)
    }

    /// Walked pieces of streets (E4); nil before the first recompute.
    func loadPieces() -> PieceCoverage? {
        guard let data = try? Data(contentsOf: piecesFile) else { return nil }
        return try? JSONDecoder().decode(PieceCoverage.self, from: data)
    }

    func savePieces(_ pieces: PieceCoverage) {
        guard let data = try? JSONEncoder().encode(pieces) else { return }
        try? data.write(to: piecesFile, options: .atomic)
    }

    func loadGoals() -> Goals {
        guard let data = try? Data(contentsOf: goalsFile) else { return Goals() }
        return (try? JSONDecoder().decode(Goals.self, from: data)) ?? Goals()
    }

    func saveGoals(_ goals: Goals) {
        guard let data = try? JSONEncoder().encode(goals) else { return }
        try? data.write(to: goalsFile, options: .atomic)
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
        let safe = name.replacingOccurrences(of: "/", with: "-")
        writeImport(fixes, name: (safe as NSString).deletingPathExtension)
        return fixes
    }

    /// Writes a walk drawn by hand afterwards as its own CSV, like an import.
    func saveDrawnWalk(_ fixes: [Fix]) {
        guard let first = fixes.first else { return }
        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withFullDate, .withTime]
        stamp.timeZone = .current
        writeImport(fixes, name: "rucne-" + stamp.string(from: first.time))
    }

    private func writeImport(_ fixes: [Fix], name: String) {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        let body = fixes.map { TrackCSV.line($0, formatter: formatter) }.joined(separator: "\n")
        let url = importDir.appendingPathComponent(name + ".csv")
        try? Data((TrackCSV.header + "\n" + body + "\n").utf8).write(to: url, options: .atomic)
    }
}

/// Challenges and the monthly goal (E5). No goal is set by default.
struct Goals: Codable, Equatable {
    var challenges: [Challenge] = []
    /// New kilometres a month; nil = off.
    var monthlyNewKm: Double?
}

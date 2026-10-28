import Foundation

/// Persists walked-segment pass counts to a local JSON file in the app's
/// Application Support directory. No networking, no iCloud sync — the data
/// never leaves the device.
///
/// MVP simplification: JSON works fine for a few tens of thousands of
/// entries but re-serializes the whole dictionary on every save. If that
/// becomes a bottleneck once the full Prague graph is loaded, swap this for
/// SQLite (e.g. via GRDB) without touching any other layer — this type is
/// the only thing that touches disk.
final class CoveragePersistence {
    let fileURL: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("coverage.json")
    }

    func loadPassCounts() -> [String: Int] {
        guard let data = try? Data(contentsOf: fileURL) else { return [:] }
        return (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:]
    }

    func savePassCounts(_ counts: [String: Int]) {
        guard let data = try? JSONEncoder().encode(counts) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

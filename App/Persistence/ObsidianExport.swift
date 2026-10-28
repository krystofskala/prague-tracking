import Foundation
import StreetTrackerCore

/// Writes every walk as `<id>.md` + `<id>.gpx` into a folder the person
/// picked once (e.g. a folder in their Obsidian vault "On my iPhone"), and
/// backs up / restores all data there. iOS keeps access through a bookmark;
/// nothing goes to any server.
final class ObsidianExport: @unchecked Sendable {
    private static let bookmarkKey = "obsidianFolderBookmark"

    /// The chosen folder, if any (resolves the saved bookmark).
    var folder: URL? {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale) else { return nil }
        if stale { remember(url) }
        return url
    }

    /// Call with the URL from the folder picker.
    @discardableResult
    func remember(_ url: URL) -> Bool {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) else {
            return false
        }
        UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
        return true
    }

    func forget() {
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
    }

    /// Writes the notes and GPX files that changed. Returns how many walks
    /// were written, or nil when no folder is set or it can't be opened.
    func export(_ walks: [Walk], meta: [String: WalkMeta]) -> Int? {
        guard let folder else { return nil }
        return withAccess(folder) {
            var written = 0
            for walk in walks {
                let m = meta[walk.id] ?? WalkMeta()
                let noteURL = folder.appendingPathComponent("\(walk.id).md")
                let existing = try? String(contentsOf: noteURL, encoding: .utf8)
                let note = WalkNote.merge(generated: WalkNote.markdown(walk, meta: m), existing: existing)
                var changed = writeIfChanged(note, to: noteURL)
                let gpx = GPX.write(walk, name: m.title ?? walk.id)
                changed = writeIfChanged(gpx, to: folder.appendingPathComponent("\(walk.id).gpx")) || changed
                if changed { written += 1 }
            }
            return written
        }
    }

    /// Copies coverage, walk names/tags and every CSV into `zaloha/`.
    func backup(files: [URL]) -> Bool {
        guard let folder else { return false }
        return withAccess(folder) {
            let target = folder.appendingPathComponent("zaloha", isDirectory: true)
            try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            var ok = true
            for file in files where FileManager.default.fileExists(atPath: file.path) {
                let dest = target.appendingPathComponent(file.lastPathComponent)
                try? FileManager.default.removeItem(at: dest)
                do { try FileManager.default.copyItem(at: file, to: dest) } catch { ok = false }
            }
            return ok
        } ?? false
    }

    /// Restores from a `zaloha/` folder the person picked: each file goes
    /// back where `destination` says (nil = skip). Existing files are kept
    /// as `.pred-obnovou` copies.
    static func restore(from picked: URL, destination: (String) -> URL?) -> Int {
        let access = picked.startAccessingSecurityScopedResource()
        defer { if access { picked.stopAccessingSecurityScopedResource() } }
        let files = (try? FileManager.default.contentsOfDirectory(at: picked, includingPropertiesForKeys: nil)) ?? []
        var restored = 0
        for file in files {
            guard let dest = destination(file.lastPathComponent) else { continue }
            if FileManager.default.fileExists(atPath: dest.path) {
                let keep = dest.appendingPathExtension("pred-obnovou")
                try? FileManager.default.removeItem(at: keep)
                try? FileManager.default.moveItem(at: dest, to: keep)
            }
            if (try? FileManager.default.copyItem(at: file, to: dest)) != nil { restored += 1 }
        }
        return restored
    }

    private func withAccess<T>(_ url: URL, _ body: () -> T) -> T? {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard FileManager.default.isWritableFile(atPath: url.path) else { return nil }
        return body()
    }

    private func writeIfChanged(_ text: String, to url: URL) -> Bool {
        if let old = try? String(contentsOf: url, encoding: .utf8), old == text { return false }
        try? Data(text.utf8).write(to: url, options: .atomic)
        return true
    }
}

import XCTest
@testable import StreetTrackerCore

final class WalkTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let prague = TimeZone(identifier: "Europe/Prague")!

    /// Walking north 4 m every 3 s.
    private func stroll(from start: TimeInterval, count: Int, lat0: Double = 50.08,
                        street: String? = "Karlova") -> [Fix] {
        (0..<count).map { i in
            Fix(time: t0.addingTimeInterval(start + 3 * Double(i)),
                coordinate: Coordinate(latitude: lat0 + Double(i) * 0.000036, longitude: 14.42),
                speed: 1.3, street: street, district: "Praha 1")
        }
    }

    func testCSVRoundTripWithQuotedFields() {
        let formatter = ISO8601DateFormatter()
        let fix = Fix(time: t0, coordinate: Coordinate(latitude: 50.087512, longitude: 14.421301),
                      accuracy: 8, speed: 1.4, street: "Na \"Příkopě\", dolní", district: "Praha 1")
        let text = TrackCSV.header + "\n" + TrackCSV.line(fix, formatter: formatter) + "\n"
        XCTAssertEqual(TrackCSV.parse(text), [fix])
    }

    func testCSVUnknownSpeedAndNoStreet() {
        let fixes = TrackCSV.parse("2027-01-15T08:00:00+01:00,50.1,14.4,65,,0,,\n")
        XCTAssertEqual(fixes.count, 1)
        XCTAssertNil(fixes[0].speed)
        XCTAssertFalse(fixes[0].walking)
        XCTAssertNil(fixes[0].street)
        XCTAssertEqual(fixes[0].accuracy, 65)
    }

    func testSplitsWalksOnPausesAndSegmentsOnGaps() {
        var fixes = stroll(from: 0, count: 100)              // ~400 m
        fixes += stroll(from: 300 + 90, count: 100, lat0: 50.0815)   // 90 s GPS gap → new segment
        fixes += stroll(from: 3600, count: 100, lat0: 50.09) // an hour later → new walk
        fixes += stroll(from: 7200, count: 10, lat0: 50.1)   // 36 m → noise
        // A ride and an inaccurate fix never count.
        fixes.append(Fix(time: t0.addingTimeInterval(100), coordinate: Coordinate(latitude: 51, longitude: 14), walking: false))
        fixes.append(Fix(time: t0.addingTimeInterval(101), coordinate: Coordinate(latitude: 51, longitude: 14), accuracy: 80))

        let walks = WalkSplitter.walks(from: fixes.shuffled(), timeZone: prague)
        XCTAssertEqual(walks.count, 2)
        XCTAssertEqual(walks[0].segments.count, 2)
        XCTAssertEqual(walks[0].distanceMeters, 2 * 99 * 4, accuracy: 10)
        XCTAssertEqual(walks[0].id, "2027-01-15-0900")
        XCTAssertEqual(walks[1].segments.count, 1)
        XCTAssertEqual(walks[0].streets, ["Karlova"])
    }

    func testGPXRoundTripKeepsSegments() {
        let walk = WalkSplitter.walks(from: stroll(from: 0, count: 100) + stroll(from: 400, count: 100, lat0: 50.0815))[0]
        let gpx = GPX.write(walk, name: "Procházka & <test>")
        XCTAssertTrue(gpx.contains("Procházka &amp; &lt;test&gt;"))
        let segments = GPX.read(Data(gpx.utf8))
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].count, 100)
        XCTAssertEqual(segments[0][0].0.latitude, 50.08, accuracy: 1e-6)
        XCTAssertEqual(segments[0][0].1, walk.start)
    }

    func testGPXFromOtherAppsWithFractionalTimes() {
        let gpx = """
        <?xml version="1.0"?><gpx xmlns="http://www.topografix.com/GPX/1/1"><trk><trkseg>
        <trkpt lat="49.1" lon="16.6"><ele>200</ele><time>2026-05-01T10:00:00.500Z</time></trkpt>
        <trkpt lat="49.2" lon="16.7"></trkpt>
        </trkseg></trk></gpx>
        """
        let segments = GPX.read(Data(gpx.utf8))
        XCTAssertEqual(segments.count, 1)
        XCTAssertNotNil(segments[0][0].1)
        XCTAssertNil(segments[0][1].1)
    }

    func testNoteHasFrontmatterAndKeepsOwnNotes() {
        let walk = WalkSplitter.walks(from: stroll(from: 0, count: 100), timeZone: prague)[0]
        let meta = WalkMeta(title: nil, tags: ["s Aničkou", "rande"], color: "#ff8800")
        let note = WalkNote.markdown(walk, meta: meta, newStreets: 3, timeZone: prague)
        XCTAssertTrue(note.hasPrefix("---\ncreated: 2027-01-15\n"))
        XCTAssertTrue(note.contains("tags: [\"prochazka\", \"s-Aničkou\", \"rande\"]"))
        XCTAssertTrue(note.contains("barva: \"#ff8800\""))
        XCTAssertTrue(note.contains("gpx: \"[[2027-01-15-0900.gpx]]\""))
        XCTAssertTrue(note.contains("nove_ulice: 3"))
        XCTAssertTrue(note.contains("- Karlova"))

        let edited = note + "Byla zima.\n[[Anička]]\n"
        let rewritten = WalkNote.merge(generated: WalkNote.markdown(walk, timeZone: prague), existing: edited)
        XCTAssertTrue(rewritten.hasSuffix(WalkNote.ownNotesHeading + "\n\nByla zima.\n[[Anička]]\n"))
        XCTAssertFalse(rewritten.contains("barva:"))
        XCTAssertEqual(WalkNote.merge(generated: "x", existing: nil), "x")
    }

    func testReplacePassCounts() {
        let store = CoverageStore(passCounts: ["a": 1])
        store.replacePassCounts(["b": 3])
        XCTAssertEqual(store.passCounts, ["b": 3])
    }
}

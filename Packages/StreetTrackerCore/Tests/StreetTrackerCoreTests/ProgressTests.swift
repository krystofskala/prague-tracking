import XCTest
@testable import StreetTrackerCore

final class ProgressTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func segment(_ id: String, name: String?, district: String? = "Praha 1", length: Double,
                         at lat: Double, lon: Double = 14.4) -> StreetSegment {
        let points = [Coordinate(latitude: lat, longitude: lon), Coordinate(latitude: lat + 0.0005, longitude: lon)]
        return StreetSegment(id: id, name: name, points: points, lengthMeters: length, district: district)
    }

    /// Karlova in two ways (90 + 10 m), Celetná, Karlova in another
    /// district, an unnamed path.
    private func graph() -> StreetGraph {
        StreetGraph(segments: [
            "k1": segment("k1", name: "Karlova", length: 90, at: 50.0),
            "k2": segment("k2", name: "Karlova", length: 10, at: 50.001),
            "c": segment("c", name: "Celetná", length: 200, at: 50.01),
            "k8": segment("k8", name: "Karlova", district: "Praha 8", length: 100, at: 50.1),
            "path": segment("path", name: nil, length: 50, at: 50.002),
        ])
    }

    func testStreetsGroupByNameAndDistrict() {
        let streets = StreetProgress.streets(graph: graph(), passCounts: ["k1": 1])
        XCTAssertEqual(streets.map(\.id), ["Celetná|Praha 1", "Karlova|Praha 1", "Karlova|Praha 8"])
        let karlova = streets[1]
        XCTAssertEqual(karlova.segmentIDs, ["k1", "k2"])
        XCTAssertEqual(karlova.fraction, 0.9, accuracy: 1e-9)
        XCTAssertTrue(karlova.isDone())
        XCTAssertFalse(karlova.isDone(strict: true))
    }

    func testPlanVisitsNearestOpenStreetsFirst() {
        let g = graph()
        let streets = StreetProgress.streets(graph: g, passCounts: ["k1": 1])
        let plan = StreetProgress.plan(from: Coordinate(latitude: 50.0, longitude: 14.4), streets: streets, graph: g)
        XCTAssertEqual(plan.map(\.street.id), ["Celetná|Praha 1", "Karlova|Praha 8"])
        let strict = StreetProgress.plan(from: Coordinate(latitude: 50.0, longitude: 14.4), streets: streets, graph: g, strict: true)
        XCTAssertEqual(strict.first?.street.id, "Karlova|Praha 1")
        XCTAssertEqual(StreetProgress.distance(from: Coordinate(latitude: 50.0, longitude: 14.4), to: streets[1], graph: g), 0, accuracy: 0.01)
    }

    func testFirstPassesDateTheFirstWalk() {
        let g = StreetGraph(segments: [
            "north": StreetSegment(id: "north", name: "north",
                                   points: [Coordinate(latitude: 50.0, longitude: 14.4), Coordinate(latitude: 50.003, longitude: 14.4)],
                                   lengthMeters: 333, district: nil),
        ])
        let walk = (0...29).map { i in
            Fix(time: t0.addingTimeInterval(Double(i) * 10), coordinate: Coordinate(latitude: 50.0 + Double(i) * 0.0001, longitude: 14.4))
        }
        let again = walk.map { Fix(time: $0.time.addingTimeInterval(86_400), coordinate: $0.coordinate) }
        let first = CoverageRebuild.firstPasses(fixes: again + walk, graph: g, matcher: MapMatcher(graph: g))
        let date = try? XCTUnwrap(first["north"])
        XCTAssertNotNil(date)
        XCTAssertLessThanOrEqual(date ?? .distantFuture, t0.addingTimeInterval(290))
        XCTAssertTrue(CoverageRebuild.firstPasses(fixes: walk, excluded: [TimeRange(from: t0, to: t0.addingTimeInterval(300))],
                                                  graph: g, matcher: MapMatcher(graph: g)).isEmpty)
    }

    // MARK: Challenges and badges

    private func walk(_ id: String, day: Int, hour: Int = 12, km: Double = 1) -> Walk {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
        let steps = Int(km * 100)
        let fixes = (0...steps).map { i in
            Fix(time: start.addingTimeInterval(Double(i) * 7), coordinate: Coordinate(latitude: 50.0 + Double(i) * 0.00009, longitude: 14.4))
        }
        return Walk(id: id, segments: [fixes])
    }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func testChallengeCountsOnlyItsSpan() {
        let walks = [walk("a", day: 1), walk("b", day: 5), walk("c", day: 20)]
        let d1 = walks[0].start, d5 = walks[1].start
        let log = ActivityLog(walks: walks, firstPasses: ["k1": d1, "k2": d5, "c": d5],
                              passCounts: ["k1": 2, "k2": 1, "c": 1, "k8": 1], graph: graph())
        XCTAssertEqual(log.undatedWalked, ["k8"])

        let span = Challenge(name: "první týden", from: d1, to: d1.addingTimeInterval(7 * 86_400), kind: .newKm, target: 1)
        XCTAssertEqual(log.progress(span), 0.3, accuracy: 1e-9)
        var walked = span
        walked.kind = .walkedKm
        XCTAssertEqual(log.progress(walked), (walks[0].distanceMeters + walks[1].distanceMeters) / 1000, accuracy: 1e-9)
        var streets = span
        streets.kind = .streetsDone
        XCTAssertEqual(log.progress(streets), 2) // Karlova and Celetná, both on day 5
        streets.district = "Praha 8"
        XCTAssertEqual(log.progress(streets), 0) // Karlova v Praze 8 is undated
    }

    func testStreetDoneDateIsWhen90PercentWasReached() {
        let d1 = t0, d2 = t0.addingTimeInterval(86_400)
        let log = ActivityLog(walks: [], firstPasses: ["k2": d1, "k1": d2], passCounts: ["k1": 1, "k2": 1], graph: graph())
        XCTAssertEqual(log.streetDoneDates()["Karlova|Praha 1"], d2)
    }

    func testBadges() {
        let walks = (1...7).map { walk("w\($0)", day: $0, hour: $0 == 3 ? 23 : 12, km: 1.5) }
        let log = ActivityLog(walks: walks, firstPasses: ["c": walks[2].start], passCounts: ["c": 1, "k8": 1], graph: graph())
        let badges = Dictionary(uniqueKeysWithValues: Badges.all(log: log, totalMeters: 1000, calendar: utc).map { ($0.id, $0) })
        XCTAssertEqual(badges["prochazky-1"]?.earnedAt, walks[0].start)
        XCTAssertFalse(badges["prochazky-10"]!.isEarned)
        XCTAssertEqual(badges["km-10"]?.earnedAt, walks[6].start)
        XCTAssertEqual(badges["noc"]?.earnedAt, walks[2].start)
        XCTAssertFalse(badges["rano"]!.isEarned)
        XCTAssertEqual(badges["tyden"]?.earnedAt, walks[6].start)
        XCTAssertEqual(badges["praha-10"]?.earnedAt, .distantPast) // k8 = 100 m before the log
        XCTAssertEqual(badges["praha-25"]?.earnedAt, walks[2].start)
        XCTAssertFalse(badges["praha-50"]!.isEarned)
        XCTAssertEqual(badges["ulice-1"]?.earnedAt, .distantPast)
    }

    func testStreakBreaksOnAMissedDay() {
        let walks = [1, 2, 3, 5, 6, 7, 8, 9, 10].map { walk("w\($0)", day: $0) }
        XCTAssertNil(Badges.streakDate(Array(walks.prefix(8)), days: 7, calendar: utc))
        XCTAssertEqual(Badges.streakDate(walks, days: 6, calendar: utc), walks[8].start)
    }
}

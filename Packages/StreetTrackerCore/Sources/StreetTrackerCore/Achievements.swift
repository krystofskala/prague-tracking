import Foundation

/// A goal the person sets for a time span (E5): "40 km nových ulic v
/// listopadu", "20 ulic na Žižkově do Vánoc".
public struct Challenge: Codable, Sendable, Identifiable, Equatable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        /// Kilometres of streets walked for the first time.
        case newKm
        /// Kilometres walked, new or not.
        case walkedKm
        /// Streets finished (90 % rule).
        case streetsDone
    }

    public var id: UUID
    public var name: String
    public var from: Date
    public var to: Date
    public var kind: Kind
    public var target: Double
    /// Only this district counts (not for `walkedKm`).
    public var district: String?

    public init(id: UUID = UUID(), name: String, from: Date, to: Date, kind: Kind, target: Double, district: String? = nil) {
        self.id = id
        self.name = name
        self.from = from
        self.to = to
        self.kind = kind
        self.target = target
        self.district = district
    }
}

/// What happened when: walks and the first pass of every segment. All the
/// numbers for challenges, the monthly goal and badges come from here.
public struct ActivityLog: Sendable {
    public let walks: [Walk]
    public let firstPasses: [String: Date]
    /// Walked segments with no date (before the log, drawn, marked by hand).
    public let undatedWalked: Set<String>
    private let segments: [String: (length: Double, district: String?, street: String?)]

    public init(walks: [Walk], firstPasses: [String: Date], passCounts: [String: Int], graph: StreetGraph) {
        self.walks = walks.sorted { $0.start < $1.start }
        self.firstPasses = firstPasses
        self.undatedWalked = Set(passCounts.filter { $0.value > 0 && firstPasses[$0.key] == nil }.keys)
        self.segments = graph.segments.mapValues { segment in
            (segment.lengthMeters, segment.district, segment.name.map { $0 + "|" + (segment.district ?? "") })
        }
    }

    public func newMeters(from: Date, to: Date, district: String? = nil) -> Double {
        firstPasses.reduce(0) { total, entry in
            guard entry.value >= from, entry.value <= to, let segment = segments[entry.key],
                  district == nil || segment.district == district else { return total }
            return total + segment.length
        }
    }

    public func walkedMeters(from: Date, to: Date) -> Double {
        walks.filter { $0.start >= from && $0.start <= to }.reduce(0) { $0 + $1.distanceMeters }
    }

    /// When each street reached 90 % (undated parts count from the start).
    public func streetDoneDates() -> [String: Date] {
        var length: [String: Double] = [:]
        var events: [String: [(Date, Double)]] = [:]
        for (id, segment) in segments {
            guard let street = segment.street else { continue }
            length[street, default: 0] += segment.length
            if undatedWalked.contains(id) {
                events[street, default: []].append((.distantPast, segment.length))
            } else if let date = firstPasses[id] {
                events[street, default: []].append((date, segment.length))
            }
        }
        var done: [String: Date] = [:]
        for (street, list) in events {
            guard let total = length[street], total > 0 else { continue }
            var walked = 0.0
            for (date, meters) in list.sorted(by: { $0.0 < $1.0 }) {
                walked += meters
                if walked / total >= StreetProgress.doneFraction {
                    done[street] = date
                    break
                }
            }
        }
        return done
    }

    public func streetsDone(from: Date, to: Date, district: String? = nil) -> Int {
        streetDoneDates().filter { street, date in
            date >= from && date <= to && (district == nil || street.hasSuffix("|" + district!))
        }.count
    }

    /// Progress in the challenge's units: km, or a count of streets.
    public func progress(_ challenge: Challenge) -> Double {
        switch challenge.kind {
        case .newKm: newMeters(from: challenge.from, to: challenge.to, district: challenge.district) / 1000
        case .walkedKm: walkedMeters(from: challenge.from, to: challenge.to) / 1000
        case .streetsDone: Double(streetsDone(from: challenge.from, to: challenge.to, district: challenge.district))
        }
    }

    /// Walked share of all streets over time, for dating coverage badges:
    /// the date the share first reached `fraction` (`.distantPast` when it
    /// was reached before the log), nil when not yet.
    public func dateReaching(fraction: Double, totalMeters: Double) -> Date? {
        guard totalMeters > 0 else { return nil }
        var walked = undatedWalked.reduce(0) { $0 + (segments[$1]?.length ?? 0) }
        if walked / totalMeters >= fraction { return .distantPast }
        for (id, date) in firstPasses.sorted(by: { $0.value < $1.value }) {
            walked += segments[id]?.length ?? 0
            if walked / totalMeters >= fraction { return date }
        }
        return nil
    }
}

public struct Badge: Sendable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let detail: String
    /// Nil = not yet; `.distantPast` = before the log.
    public let earnedAt: Date?

    public var isEarned: Bool { earnedAt != nil }
}

public enum Badges {
    public static func all(log: ActivityLog, totalMeters: Double, calendar: Calendar = .current) -> [Badge] {
        var badges: [Badge] = []
        let walks = log.walks

        for n in [1, 10, 50, 100] {
            badges.append(Badge(id: "prochazky-\(n)", title: n == 1 ? "První procházka" : "\(n) procházek",
                                detail: n == 1 ? "Appka zaznamenala první procházku." : "Zaznamenáno \(n) procházek.",
                                earnedAt: walks.count >= n ? walks[n - 1].start : nil))
        }

        var total = 0.0
        var kmDates: [Int: Date] = [:]
        for walk in walks {
            total += walk.distanceMeters
            for km in [10, 100, 500] where kmDates[km] == nil && total >= Double(km) * 1000 {
                kmDates[km] = walk.start
            }
        }
        for km in [10, 100, 500] {
            badges.append(Badge(id: "km-\(km)", title: "\(km) km", detail: "Nachozeno \(km) km.", earnedAt: kmDates[km]))
        }

        for percent in [1, 5, 10, 25, 50, 100] {
            badges.append(Badge(id: "praha-\(percent)", title: "\(percent) % Prahy",
                                detail: "Prošlo \(percent) % délky pražských ulic.",
                                earnedAt: log.dateReaching(fraction: Double(percent) / 100, totalMeters: totalMeters)))
        }

        let night = walks.first { hour($0.start, calendar) >= 22 || hour($0.start, calendar) < 4 }
        badges.append(Badge(id: "noc", title: "Noční chodec", detail: "Procházka začala mezi 22. a 4. hodinou.", earnedAt: night?.start))
        let morning = walks.first { (5..<7).contains(hour($0.start, calendar)) }
        badges.append(Badge(id: "rano", title: "Ranní ptáče", detail: "Procházka začala mezi 5. a 7. hodinou.", earnedAt: morning?.start))
        badges.append(Badge(id: "tyden", title: "Týden v kuse", detail: "Sedm dní po sobě aspoň jedna procházka.",
                            earnedAt: streakDate(walks, days: 7, calendar: calendar)))

        let streets = log.streetDoneDates().values.sorted()
        for n in [1, 10, 100] {
            badges.append(Badge(id: "ulice-\(n)", title: n == 1 ? "První celá ulice" : "\(n) celých ulic",
                                detail: "Ulice se počítá od 90 % délky.",
                                earnedAt: streets.count >= n ? streets[n - 1] : nil))
        }
        return badges
    }

    private static func hour(_ date: Date, _ calendar: Calendar) -> Int {
        calendar.component(.hour, from: date)
    }

    /// The start of the walk on the last day of the first `days`-day streak.
    static func streakDate(_ walks: [Walk], days: Int, calendar: Calendar) -> Date? {
        var run = 0
        var previous: Date?
        for walk in walks {
            let day = calendar.startOfDay(for: walk.start)
            if let previous, day == previous { continue }
            if let previous, calendar.date(byAdding: .day, value: 1, to: previous) == day {
                run += 1
            } else {
                run = 1
            }
            previous = day
            if run >= days { return walk.start }
        }
        return nil
    }
}

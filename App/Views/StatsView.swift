import SwiftUI
import MapKit
import StreetTrackerCore

/// Overviews (E5): unwalked streets and a walk plan through them,
/// challenges and the monthly goal, badges, districts, a personal heatmap.
struct StatsView: View {
    @EnvironmentObject private var viewModel: TrackingViewModel
    @State private var tab = Tab.streets

    enum Tab: String, CaseIterable {
        case streets = "Ulice"
        case goals = "Výzvy"
        case badges = "Odznaky"
        case districts = "Čtvrti"
        case heatmap = "Mapa"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Přehled", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)

                if viewModel.activity == nil {
                    ProgressView("Počítám z celé historie…")
                        .frame(maxHeight: .infinity)
                } else {
                    switch tab {
                    case .streets: StreetsTab()
                    case .goals: GoalsTab()
                    case .badges: BadgesTab()
                    case .districts: DistrictsTab()
                    case .heatmap: HeatmapTab()
                    }
                }
            }
            .navigationTitle("Přehledy")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { viewModel.refreshStats() }
    }
}

// MARK: Streets

private struct StreetsTab: View {
    @EnvironmentObject private var viewModel: TrackingViewModel
    @State private var district: String?
    @State private var order = Order.nearest
    @State private var strict = false
    @State private var rows: [Row] = []

    enum Order: String, CaseIterable {
        case nearest = "Nejblíž"
        case shortest = "Nejkratší"
        case started = "Rozpracované"
    }

    struct Row: Identifiable {
        let street: StreetStatus
        let distance: Double?
        var id: String { street.id }
    }

    private var inDistrict: [StreetStatus] {
        viewModel.streets.filter { district == nil || $0.district == district }
    }

    private var districts: [String] {
        Array(Set(viewModel.streets.compactMap(\.district))).sorted { $0.localizedCompare($1) == .orderedAscending }
    }

    var body: some View {
        List {
            Section {
                Picker("Čtvrť", selection: $district) {
                    Text("Celá Praha").tag(String?.none)
                    ForEach(districts, id: \.self) { Text($0).tag(Optional($0)) }
                }
                Picker("Řadit", selection: $order) {
                    ForEach(Order.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Toggle("Přísně (celá ulice, ne 90 %)", isOn: $strict)
                let done = inDistrict.filter { $0.isDone(strict: strict) }.count
                LabeledContent("Hotové ulice", value: "\(done) z \(inDistrict.count)")
                NavigationLink("Naplánuj procházku po neprošlých") {
                    PlanView(streets: inDistrict, strict: strict)
                }
                .disabled(viewModel.lastLocation == nil)
            } footer: {
                Text("Ulice se počítá jako hotová od 90 % délky, jako na CityStrides. Přísný režim chce celou.")
            }
            Section("Neprošlé") {
                ForEach(rows.prefix(200)) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.street.name)
                        HStack {
                            Text(row.street.district ?? "")
                            Text(verbatim: "\(Int(row.street.fraction * 100)) % z \(Int(row.street.lengthMeters)) m")
                            if let d = row.distance { Text(verbatim: "· \(Self.format(d))") }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .task(id: "\(district ?? "")|\(order)|\(strict)|\(viewModel.streets.count)") { sort() }
    }

    private func sort() {
        let here = viewModel.lastLocation
        let graph = viewModel.graph
        let open = inDistrict.filter { !$0.isDone(strict: strict) }
        var rows = open.map { street in
            Row(street: street, distance: here.map { StreetProgress.distance(from: $0, to: street, graph: graph) })
        }
        switch order {
        case .nearest where here != nil: rows.sort { ($0.distance ?? 0) < ($1.distance ?? 0) }
        case .started: rows.sort { $0.street.fraction > $1.street.fraction }
        default: rows.sort { $0.street.lengthMeters < $1.street.lengthMeters }
        }
        self.rows = rows
    }

    static func format(_ meters: Double) -> String {
        meters < 1000 ? "\(Int(meters)) m" : "\((meters / 1000).formatted(.number.precision(.fractionLength(1)))) km"
    }
}

/// The nearest unfinished streets in walking order, on a map.
private struct PlanView: View {
    @EnvironmentObject private var viewModel: TrackingViewModel
    let streets: [StreetStatus]
    let strict: Bool
    @State private var count = 6

    private var stops: [(street: StreetStatus, point: Coordinate)] {
        guard let here = viewModel.lastLocation else { return [] }
        return StreetProgress.plan(from: here, streets: streets, graph: viewModel.graph, count: count, strict: strict)
    }

    var body: some View {
        let stops = stops
        VStack(spacing: 0) {
            WalkMapView(lines: lines(stops))
            List {
                Stepper("Ulic v plánu: \(count)", value: $count, in: 2...15)
                ForEach(Array(stops.enumerated()), id: \.offset) { i, stop in
                    HStack {
                        Text("\(i + 1)").font(.headline).frame(width: 28)
                        VStack(alignment: .leading) {
                            Text(stop.street.name)
                            Text(verbatim: "\(stop.street.district ?? "") · \(Int(stop.street.fraction * 100)) %")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(height: 300)
        }
        .navigationTitle("Plán procházky")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func lines(_ stops: [(street: StreetStatus, point: Coordinate)]) -> [WalkMapView.Line] {
        var lines: [WalkMapView.Line] = []
        if let here = viewModel.lastLocation {
            lines.append(.init(id: "poradi", points: [here] + stops.map(\.point), color: .systemGray, width: 2, dashed: true))
        }
        for (i, stop) in stops.enumerated() {
            for id in stop.street.segmentIDs {
                guard let segment = viewModel.graph.segments[id] else { continue }
                lines.append(.init(id: "\(i)-\(id)", points: segment.points, color: .systemPurple, width: 6))
            }
        }
        return lines
    }
}

// MARK: Challenges and the monthly goal

private struct GoalsTab: View {
    @EnvironmentObject private var viewModel: TrackingViewModel
    @State private var adding = false

    private var month: (from: Date, to: Date) {
        let calendar = Calendar.current
        let from = calendar.dateInterval(of: .month, for: Date())!
        return (from.start, from.end)
    }

    var body: some View {
        let log = viewModel.activity!
        List {
            Section {
                Toggle("Měsíční cíl nových km", isOn: Binding(
                    get: { viewModel.goals.monthlyNewKm != nil },
                    set: { on in
                        var goals = viewModel.goals
                        goals.monthlyNewKm = on ? 20 : nil
                        viewModel.saveGoals(goals)
                    }
                ))
                if let target = viewModel.goals.monthlyNewKm {
                    Stepper("Cíl: \(Int(target)) km", value: Binding(
                        get: { target },
                        set: { var goals = viewModel.goals; goals.monthlyNewKm = $0; viewModel.saveGoals(goals) }
                    ), in: 5...300, step: 5)
                    progressRow(done: log.newMeters(from: month.from, to: month.to) / 1000, target: target, unit: "km")
                }
            } header: {
                Text("Tento měsíc")
            } footer: {
                Text("Počítají se jen ulice prošlé poprvé. Cíl je vypnutý, dokud si ho nezapneš.")
            }

            Section("Výzvy") {
                ForEach(viewModel.goals.challenges) { challenge in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(challenge.name).font(.headline)
                        Text(verbatim: "\(challenge.from.formatted(date: .abbreviated, time: .omitted)) – \(challenge.to.formatted(date: .abbreviated, time: .omitted))"
                             + (challenge.district.map { " · \($0)" } ?? ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        progressRow(done: log.progress(challenge), target: challenge.target,
                                    unit: challenge.kind == .streetsDone ? "ulic" : "km")
                    }
                }
                .onDelete { offsets in
                    var goals = viewModel.goals
                    goals.challenges.remove(atOffsets: offsets)
                    viewModel.saveGoals(goals)
                }
                Button("Nová výzva") { adding = true }
            }
        }
        .sheet(isPresented: $adding) {
            NewChallengeView().environmentObject(viewModel)
        }
    }

    private func progressRow(done: Double, target: Double, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ProgressView(value: min(done / max(target, 0.001), 1))
                .tint(done >= target ? .green : .accentColor)
            Text(verbatim: "\(done.formatted(.number.precision(.fractionLength(unit == "ulic" ? 0 : 1)))) z \(Int(target)) \(unit)"
                 + (done >= target ? " · splněno" : ""))
                .font(.caption)
                .monospacedDigit()
        }
    }
}

private struct NewChallengeView: View {
    @EnvironmentObject private var viewModel: TrackingViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind = Challenge.Kind.newKm
    @State private var target = 20.0
    @State private var from = Calendar.current.startOfDay(for: Date())
    @State private var to = Calendar.current.date(byAdding: .month, value: 1, to: Date())!
    @State private var district: String?

    private var districts: [String] {
        Array(Set(viewModel.streets.compactMap(\.district))).sorted { $0.localizedCompare($1) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Název, třeba Žižkov do Vánoc", text: $name)
                    .accessibilityIdentifier("nazev-vyzvy")
                Picker("Co", selection: $kind) {
                    Text("Nové km").tag(Challenge.Kind.newKm)
                    Text("Nachozené km").tag(Challenge.Kind.walkedKm)
                    Text("Hotové ulice").tag(Challenge.Kind.streetsDone)
                }
                Stepper("Cíl: \(Int(target)) \(kind == .streetsDone ? "ulic" : "km")", value: $target, in: 1...1000, step: kind == .streetsDone ? 1 : 5)
                DatePicker("Od", selection: $from, displayedComponents: .date)
                DatePicker("Do", selection: $to, in: from..., displayedComponents: .date)
                if kind != .walkedKm {
                    Picker("Čtvrť", selection: $district) {
                        Text("Celá Praha").tag(String?.none)
                        ForEach(districts, id: \.self) { Text($0).tag(Optional($0)) }
                    }
                }
            }
            .navigationTitle("Nová výzva")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Zrušit") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Přidat") {
                        let end = Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: Calendar.current.startOfDay(for: to))!
                        var goals = viewModel.goals
                        goals.challenges.append(Challenge(name: name.isEmpty ? "Výzva" : name, from: from, to: end, kind: kind,
                                                          target: target, district: kind == .walkedKm ? nil : district))
                        viewModel.saveGoals(goals)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: Badges

private struct BadgesTab: View {
    @EnvironmentObject private var viewModel: TrackingViewModel

    var body: some View {
        let badges = Badges.all(log: viewModel.activity!, totalMeters: viewModel.totalStreetMeters)
        ScrollView {
            Text(verbatim: "Získáno \(badges.filter(\.isEarned).count) z \(badges.count)")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 12) {
                ForEach(badges) { badge in
                    VStack(spacing: 6) {
                        Image(systemName: badge.isEarned ? "rosette" : "lock")
                            .font(.largeTitle)
                            .foregroundStyle(badge.isEarned ? Color.orange : Color.secondary)
                        Text(badge.title).font(.headline).multilineTextAlignment(.center)
                        Text(badge.detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        if let date = badge.earnedAt {
                            Text(date == .distantPast ? "před záznamem" : date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption2)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, minHeight: 150)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                    .opacity(badge.isEarned ? 1 : 0.55)
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: Districts

private struct DistrictsTab: View {
    @EnvironmentObject private var viewModel: TrackingViewModel

    var body: some View {
        let rows = viewModel.districtCoverage
            .filter { $0.key != "Unknown" }
            .sorted { $0.value > $1.value }
        List(rows, id: \.key) { row in
            let fraction = row.value
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(row.key)
                    Spacer()
                    Text(verbatim: "\((fraction * 100).formatted(.number.precision(.fractionLength(fraction < 0.01 ? 2 : 1)))) %")
                        .monospacedDigit()
                }
                ProgressView(value: fraction)
            }
        }
    }
}

// MARK: Heatmap

/// Every walk drawn faintly on top of each other: often walked streets
/// come out strong.
private struct HeatmapTab: View {
    @EnvironmentObject private var viewModel: TrackingViewModel
    @State private var filter = Filter.all

    enum Filter: String, CaseIterable {
        case all = "Vše"
        case night = "Noc"
        case weekend = "Víkend"
        case month = "Měsíc"
    }

    private var walks: [Walk] {
        let calendar = Calendar.current
        return viewModel.editedWalks.filter { walk in
            switch filter {
            case .all: return true
            case .night:
                let hour = calendar.component(.hour, from: walk.start)
                return hour >= 20 || hour < 5
            case .weekend: return calendar.isDateInWeekend(walk.start)
            case .month: return calendar.isDate(walk.start, equalTo: Date(), toGranularity: .month)
            }
        }
    }

    var body: some View {
        let walks = walks
        VStack(spacing: 0) {
            Picker("Které procházky", selection: $filter) {
                ForEach(Filter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 4)
            Text(verbatim: "Procházky: \(walks.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
            WalkMapView(lines: walks.flatMap { walk in
                WalkMapView.lines(for: walk, color: UIColor.systemRed.withAlphaComponent(0.35), width: 5, id: walk.id)
            })
            .id(filter)
        }
    }
}

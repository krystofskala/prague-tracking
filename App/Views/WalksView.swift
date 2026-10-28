import SwiftUI
import MapKit
import StreetTrackerCore

/// Every walk anywhere in the world, newest first, grouped by month or tag.
struct WalksView: View {
    @EnvironmentObject private var viewModel: TrackingViewModel
    @State private var tagFilter: String?
    @State private var grouping = Grouping.month
    @State private var drawingWalk = false

    enum Grouping: String, CaseIterable {
        case month = "Podle měsíce"
        case tag = "Podle štítku"
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sections, id: \.0) { title, walks in
                    Section(title) {
                        ForEach(walks, id: \.id) { walk in
                            NavigationLink(value: walk.id) {
                                WalkRow(walk: walk, edited: viewModel.edited(walk),
                                        meta: viewModel.walkMeta[walk.id] ?? WalkMeta())
                            }
                        }
                    }
                }
            }
            .overlay {
                if shown.isEmpty {
                    ContentUnavailableView(
                        tagFilter == nil ? "Zatím žádné procházky" : "Nic se štítkem #\(tagFilter!)",
                        systemImage: "figure.walk",
                        description: Text(tagFilter == nil ? "Procházka se objeví, jakmile ujdeš aspoň 200 m." : "Zkus jiný štítek."))
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { drawingWalk = true } label: {
                        Label("Nová procházka ručně", systemImage: "hand.draw")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Seskupit", selection: $grouping) {
                            ForEach(Grouping.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        Picker("Štítek", selection: $tagFilter) {
                            Text("Všechny štítky").tag(String?.none)
                            ForEach(viewModel.allTags, id: \.self) { Text("#\($0)").tag(String?.some($0)) }
                        }
                    } label: {
                        Label("Třídit a filtrovat", systemImage: tagFilter == nil
                              ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $drawingWalk) {
                NewDrawnWalkView().environmentObject(viewModel)
            }
            .navigationTitle(tagFilter.map { "#\($0)" } ?? "Procházky")
            .navigationDestination(for: String.self) { id in
                if let walk = viewModel.walks.first(where: { $0.id == id }) {
                    WalkDetailView(walk: walk)
                }
            }
        }
    }

    private var shown: [Walk] {
        guard let tagFilter else { return viewModel.walks }
        return viewModel.walks.filter { viewModel.walkMeta[$0.id]?.tags.contains(tagFilter) == true }
    }

    private var sections: [(String, [Walk])] {
        var order: [String] = []
        var groups: [String: [Walk]] = [:]
        func add(_ walk: Walk, to key: String) {
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(walk)
        }
        switch grouping {
        case .month:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "cs_CZ")
            formatter.dateFormat = "LLLL yyyy"
            for walk in shown { add(walk, to: formatter.string(from: walk.start)) }
            return order.map { ($0, groups[$0]!) }
        case .tag:
            for walk in shown {
                let tags = viewModel.walkMeta[walk.id]?.tags ?? []
                for tag in tags.isEmpty ? ["bez štítku"] : tags.map({ "#\($0)" }) { add(walk, to: tag) }
            }
            return order.sorted { a, b in
                (a == "bez štítku" ? 1 : 0, a) < (b == "bez štítku" ? 1 : 0, b)
            }.map { ($0, groups[$0]!) }
        }
    }
}

struct WalkRow: View {
    let walk: Walk
    /// Nil when the whole walk was removed in editing.
    let edited: Walk?
    let meta: WalkMeta

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(hex: meta.color) ?? .orange)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(meta.title ?? walk.start.formatted(date: .abbreviated, time: .shortened))
                    .strikethrough(edited == nil)
                Text(verbatim: edited.map { "\($0.distanceMeters.kilometres) · \($0.place)" + (meta.edit == nil ? "" : " · upraveno") }
                     ?? "celá smazaná, jde vrátit")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !meta.tags.isEmpty {
                    Text(meta.tags.map { "#\($0)" }.joined(separator: " "))
                        .font(.caption2)
                        .foregroundStyle(Color(hex: meta.color) ?? .secondary)
                }
            }
        }
    }
}

/// Colours offered for walks: distinct on the map in light and dark mode.
enum WalkColors {
    static let palette = ["#ff9500", "#ff3b30", "#ff2d92", "#af52de", "#5856d6", "#007aff", "#30b0c7", "#34c759"]
}

struct WalkDetailView: View {
    @EnvironmentObject private var viewModel: TrackingViewModel
    let walk: Walk
    @State private var title = ""
    @State private var newTag = ""

    private var meta: WalkMeta { viewModel.walkMeta[walk.id] ?? WalkMeta() }
    private var edited: Walk? { viewModel.edited(walk) }
    private var color: Color { Color(hex: meta.color) ?? .orange }

    var body: some View {
        List {
            WalkMapView(lines: WalkMapView.lines(for: edited ?? walk, color: UIColor(color)))
                .frame(height: 300)
                .listRowInsets(EdgeInsets())
            Section("Název") {
                TextField(walk.start.formatted(date: .abbreviated, time: .shortened), text: $title)
                    .submitLabel(.done)
                    .onSubmit(saveTitle)
                    .accessibilityIdentifier("nazev")
            }
            Section("Barva") {
                HStack {
                    ForEach(WalkColors.palette, id: \.self) { hex in
                        Button {
                            var m = meta
                            m.color = hex
                            viewModel.updateMeta(m, for: walk.id)
                        } label: {
                            Circle()
                                .fill(Color(hex: hex)!)
                                .frame(width: 28, height: 28)
                                .overlay(Circle().stroke(.primary, lineWidth: meta.color == hex ? 3 : 0))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Barva \(hex)")
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            Section("Štítky") {
                if !meta.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(meta.tags, id: \.self) { tag in
                                Button {
                                    var m = meta
                                    m.tags.removeAll { $0 == tag }
                                    viewModel.updateMeta(m, for: walk.id)
                                } label: {
                                    Label("#\(tag)", systemImage: "xmark")
                                        .labelStyle(TagLabelStyle())
                                }
                                .buttonStyle(.bordered)
                                .tint(color)
                            }
                        }
                    }
                }
                TextField("Přidat štítek (třeba večer, s Aničkou)", text: $newTag)
                    .submitLabel(.done)
                    .textInputAutocapitalization(.never)
                    .onSubmit { addTag(newTag) }
                    .accessibilityIdentifier("novy-stitek")
                let unused = viewModel.allTags.filter { !meta.tags.contains($0) }
                if !unused.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(unused, id: \.self) { tag in
                                Button("+ #\(tag)") { addTag(tag) }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }
            if let edited {
                Section {
                    LabeledContent("Délka", value: edited.distanceMeters.kilometres)
                    LabeledContent("Čas", value: "\(edited.start.formatted(date: .omitted, time: .shortened))–\(edited.end.formatted(date: .omitted, time: .shortened))")
                    LabeledContent("Kde", value: edited.place)
                    if edited.segments.count > 1 {
                        LabeledContent("Výpadky GPS", value: "\(edited.segments.count - 1)")
                    }
                }
            }
            Section("Trasa") {
                NavigationLink("Upravit trasu") { WalkEditView(walk: walk) }
                if meta.edit != nil {
                    Button("Vrátit původní trasu", role: .destructive) {
                        var m = meta
                        m.edit = nil
                        viewModel.updateMeta(m, for: walk.id)
                    }
                }
            }
            if let edited, !edited.streets.isEmpty {
                Section("Ulice (\(edited.streets.count))") {
                    ForEach(edited.streets, id: \.self) { Text($0) }
                }
            }
        }
        .navigationTitle(meta.title ?? walk.start.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { title = meta.title ?? "" }
        .onDisappear(perform: saveTitle)
    }

    private func saveTitle() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        let value = trimmed.isEmpty ? nil : trimmed
        guard value != meta.title else { return }
        var m = meta
        m.title = value
        viewModel.updateMeta(m, for: walk.id)
    }

    private func addTag(_ raw: String) {
        let tag = raw.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#")).lowercased()
        newTag = ""
        guard !tag.isEmpty, !meta.tags.contains(tag) else { return }
        var m = meta
        m.tags.append(tag)
        viewModel.updateMeta(m, for: walk.id)
    }
}

/// "#tag ×" with the cross after the text.
struct TagLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon.font(.caption2)
        }
    }
}

extension Walk {
    /// Districts in Prague, otherwise "mimo Prahu".
    var place: String {
        districts.isEmpty ? "mimo Prahu" : districts.prefix(3).joined(separator: ", ")
    }
}

extension Double {
    var kilometres: String {
        (self / 1000).formatted(.number.precision(.fractionLength(1))) + " km"
    }
}

extension Color {
    init?(hex: String?) {
        guard let hex, hex.hasPrefix("#"), hex.count == 7, let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xff) / 255, green: Double((value >> 8) & 0xff) / 255, blue: Double(value & 0xff) / 255)
    }
}

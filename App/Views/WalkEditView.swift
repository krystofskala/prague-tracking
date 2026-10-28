import SwiftUI
import MapKit
import StreetTrackerCore

/// Fixing a walk by hand (E3): trim the start or end, remove a piece (a
/// tram ride taken for walking), draw a piece the GPS missed. The CSV
/// stays as recorded; the edit is saved next to it and can be undone.
struct WalkEditView: View {
    @EnvironmentObject private var viewModel: TrackingViewModel
    @Environment(\.dismiss) private var dismiss
    let walk: Walk

    @State private var mode = Mode.trim
    @State private var removed: [TimeRange] = []
    @State private var drawn: [[Coordinate]] = []
    @State private var first = 0.0
    @State private var last = 0.0
    @State private var cutFrom = 0.0
    @State private var cutTo = 0.0

    enum Mode: String, CaseIterable {
        case trim = "Oříznout"
        case cut = "Smazat kus"
        case draw = "Dokreslit"
    }

    private var fixes: [Fix] { walk.fixes }
    private var lastIndex: Double { Double(max(fixes.count - 1, 1)) }
    private var color: UIColor { UIColor(Color(hex: viewModel.walkMeta[walk.id]?.color) ?? .orange) }

    private var edit: WalkEdit {
        WalkEdit(
            trimStart: Int(first) > 0 ? fixes[Int(first)].time : nil,
            trimEnd: Int(last) < fixes.count - 1 ? fixes[Int(last)].time : nil,
            removed: removed,
            drawn: drawn
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            WalkMapView(lines: lines, drawing: mode == .draw, snap: { [matcher = viewModel.streetMatcher] in matcher?.snap($0) }) { piece in
                drawn.append(piece)
            }
            Form {
                Picker("Úprava", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                switch mode {
                case .trim: trimControls
                case .cut: cutControls
                case .draw: drawControls
                }
            }
            .frame(height: 290)
        }
        .navigationTitle("Upravit trasu")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Uložit", action: save)
            }
        }
        .onAppear(perform: load)
    }

    // MARK: Controls

    @ViewBuilder private var trimControls: some View {
        Section {
            indexSlider("Začátek", value: $first)
                .onChange(of: first) { if first >= last { first = max(last - 1, 0) } }
            indexSlider("Konec", value: $last)
                .onChange(of: last) { if last <= first { last = min(first + 1, lastIndex) } }
        } footer: {
            Text("Šedá je původní záznam, barevná zůstane.")
        }
    }

    @ViewBuilder private var cutControls: some View {
        Section {
            indexSlider("Od", value: $cutFrom)
                .onChange(of: cutFrom) { if cutTo < cutFrom { cutTo = cutFrom } }
            indexSlider("Do", value: $cutTo)
                .onChange(of: cutTo) { if cutFrom > cutTo { cutFrom = cutTo } }
            Button("Smazat vybraný kus", role: .destructive) {
                removed.append(TimeRange(from: fixes[Int(cutFrom)].time, to: fixes[Int(cutTo)].time))
            }
            .disabled(cutTo <= cutFrom)
        } footer: {
            Text("Červeně je kus, který smažeš. Třeba jízda tramvají, kterou GPS vzala jako chůzi.")
        }
        if !removed.isEmpty {
            Section("Smazané kusy") {
                ForEach(Array(removed.enumerated()), id: \.offset) { i, range in
                    HStack {
                        Text("\(range.from.formatted(date: .omitted, time: .shortened))–\(range.to.formatted(date: .omitted, time: .shortened))")
                        Spacer()
                        Button("Vrátit") { removed.remove(at: i) }
                    }
                }
            }
        }
    }

    @ViewBuilder private var drawControls: some View {
        Section {
            Text("Táhni prstem po mapě, kudy jsi šel. Čára se přichytí k nejbližší ulici. Mapou teď hýbeš dvěma prsty.")
                .font(.callout)
        }
        if !drawn.isEmpty {
            Section("Dokreslené kusy") {
                ForEach(Array(drawn.enumerated()), id: \.offset) { i, piece in
                    HStack {
                        Text("Kus \(i + 1) · \(Geo.polylineLength(piece).rounded().formatted()) m")
                        Spacer()
                        Button("Smazat", role: .destructive) { drawn.remove(at: i) }
                    }
                }
            }
        }
    }

    private func indexSlider(_ label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label).frame(width: 70, alignment: .leading)
            Slider(value: value, in: 0...lastIndex, step: 1)
            Text(fixes[min(Int(value.wrappedValue), fixes.count - 1)].time.formatted(date: .omitted, time: .shortened))
                .monospacedDigit()
                .font(.caption)
        }
    }

    // MARK: Map

    private var lines: [WalkMapView.Line] {
        var lines = WalkMapView.lines(for: walk, color: .systemGray3, width: 3, id: "puvodni")
        if let kept = walk.applying(edit) {
            lines += WalkMapView.lines(for: kept, color: color, width: 5)
        }
        if mode == .cut, cutTo > cutFrom {
            let piece = fixes[Int(cutFrom)...Int(cutTo)].map(\.coordinate)
            lines.append(.init(id: "vyber", points: piece, color: .systemRed, width: 7))
        }
        return lines
    }

    // MARK: Load / save

    private func load() {
        let saved = viewModel.walkMeta[walk.id]?.edit ?? WalkEdit()
        removed = saved.removed
        drawn = saved.drawn
        first = Double(saved.trimStart.flatMap { start in fixes.firstIndex { $0.time >= start } } ?? 0)
        last = Double(saved.trimEnd.flatMap { end in fixes.lastIndex { $0.time <= end } } ?? fixes.count - 1)
        cutFrom = first
        cutTo = first
    }

    private func save() {
        var meta = viewModel.walkMeta[walk.id] ?? WalkMeta()
        meta.edit = edit.isEmpty ? nil : edit
        viewModel.updateMeta(meta, for: walk.id)
        dismiss()
    }
}

/// Lines on their own map, each GPS segment separately so a gap is never
/// drawn through houses. Optionally lets a finger draw a new piece.
struct WalkMapView: UIViewRepresentable {
    struct Line: Equatable {
        var id: String
        var points: [Coordinate]
        var color: UIColor
        var width: CGFloat
        var dashed = false
    }

    let lines: [Line]
    var drawing = false
    /// Where to look when there are no lines yet.
    var center: Coordinate?
    var snap: (Coordinate) -> Coordinate? = { $0 }
    var onDraw: (([Coordinate]) -> Void)?

    /// A walk's recorded segments plus its hand-drawn pieces (dashed).
    static func lines(for walk: Walk, color: UIColor, width: CGFloat = 4, id: String = "trasa") -> [Line] {
        walk.segments.enumerated().map { i, segment in
            Line(id: "\(id)-\(i)", points: segment.map(\.coordinate), color: color, width: width)
        } + walk.drawn.enumerated().map { i, piece in
            Line(id: "\(id)-ruka-\(i)", points: piece, color: color, width: width, dashed: true)
        }
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.panned(_:)))
        pan.maximumNumberOfTouches = 1
        map.addGestureRecognizer(pan)
        context.coordinator.pan = pan
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.snap = snap
        coordinator.onDraw = onDraw
        coordinator.pan?.isEnabled = drawing
        // One finger draws; two fingers still move the map.
        map.panGestureRecognizers.forEach { $0.minimumNumberOfTouches = drawing ? 2 : 1 }

        if !coordinator.fitted, lines.isEmpty, let center {
            coordinator.fitted = true
            map.setRegion(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude),
                                             latitudinalMeters: 1500, longitudinalMeters: 1500), animated: false)
        }
        guard lines != coordinator.lines else { return }
        coordinator.lines = lines
        map.removeOverlays(map.overlays.filter { $0 is StyledPolyline && $0 !== coordinator.sketch })
        var rect = MKMapRect.null
        for line in lines where line.points.count >= 2 {
            let overlay = StyledPolyline(line)
            map.addOverlay(overlay)
            rect = rect.union(overlay.boundingMapRect)
        }
        if !coordinator.fitted, !rect.isNull {
            coordinator.fitted = true
            map.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 30, left: 30, bottom: 30, right: 30), animated: false)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class StyledPolyline: MKPolyline {
        var style = Line(id: "", points: [], color: .systemOrange, width: 4)

        convenience init(_ line: Line) {
            let coords = line.points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            self.init(coordinates: coords, count: coords.count)
            style = line
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var lines: [Line] = []
        var fitted = false
        var pan: UIPanGestureRecognizer?
        var snap: (Coordinate) -> Coordinate? = { $0 }
        var onDraw: (([Coordinate]) -> Void)?
        var drawingPoints: [Coordinate] = []
        var sketch: StyledPolyline?

        @objc func panned(_ gesture: UIPanGestureRecognizer) {
            guard let map = gesture.view as? MKMapView else { return }
            switch gesture.state {
            case .began:
                drawingPoints = []
                fallthrough
            case .changed:
                let c = map.convert(gesture.location(in: map), toCoordinateFrom: map)
                guard let point = snap(Coordinate(latitude: c.latitude, longitude: c.longitude)) else { return }
                if let previous = drawingPoints.last, Geo.distance(previous, point) < 3 { return }
                drawingPoints.append(point)
                if let sketch { map.removeOverlay(sketch) }
                let line = StyledPolyline(Line(id: "kresli", points: drawingPoints, color: .systemPurple, width: 5, dashed: true))
                sketch = line
                map.addOverlay(line)
            default:
                if let sketch { map.removeOverlay(sketch) }
                sketch = nil
                if drawingPoints.count >= 2 { onDraw?(drawingPoints) }
                drawingPoints = []
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? StyledPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: line)
            renderer.strokeColor = line.style.color
            renderer.lineWidth = line.style.width
            renderer.lineCap = .round
            if line.style.dashed { renderer.lineDashPattern = [6, 6] }
            return renderer
        }
    }
}

private extension MKMapView {
    /// MapKit's own pan recognizers (moving the map).
    var panGestureRecognizers: [UIPanGestureRecognizer] {
        subviews.flatMap { $0.gestureRecognizers ?? [] }.compactMap { $0 as? UIPanGestureRecognizer }
    }
}

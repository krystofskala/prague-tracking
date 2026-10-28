import SwiftUI
import MapKit
import StreetTrackerCore

/// Every walk anywhere in the world, newest first, grouped by month.
struct WalksView: View {
    @EnvironmentObject private var viewModel: TrackingViewModel

    var body: some View {
        NavigationStack {
            List {
                ForEach(months, id: \.0) { month, walks in
                    Section(month) {
                        ForEach(walks, id: \.id) { walk in
                            NavigationLink(value: walk.id) {
                                WalkRow(walk: walk, meta: viewModel.walkMeta[walk.id] ?? WalkMeta())
                            }
                        }
                    }
                }
            }
            .overlay {
                if viewModel.walks.isEmpty {
                    ContentUnavailableView("Zatím žádné procházky", systemImage: "figure.walk",
                                           description: Text("Procházka se objeví, jakmile ujdeš aspoň 200 m."))
                }
            }
            .navigationTitle("Procházky")
            .navigationDestination(for: String.self) { id in
                if let walk = viewModel.walks.first(where: { $0.id == id }) {
                    WalkDetailView(walk: walk)
                }
            }
        }
    }

    private var months: [(String, [Walk])] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "cs_CZ")
        formatter.dateFormat = "LLLL yyyy"
        var order: [String] = []
        var groups: [String: [Walk]] = [:]
        for walk in viewModel.walks {
            let key = formatter.string(from: walk.start)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(walk)
        }
        return order.map { ($0, groups[$0]!) }
    }
}

struct WalkRow: View {
    let walk: Walk
    let meta: WalkMeta

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(hex: meta.color) ?? .orange)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(meta.title ?? walk.start.formatted(date: .abbreviated, time: .shortened))
                Text(verbatim: "\(walk.distanceMeters.kilometres) · \(walk.place)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !meta.tags.isEmpty {
                    Text(meta.tags.map { "#\($0)" }.joined(separator: " "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct WalkDetailView: View {
    let walk: Walk

    var body: some View {
        List {
            WalkMapView(walk: walk)
                .frame(height: 320)
                .listRowInsets(EdgeInsets())
            Section {
                LabeledContent("Délka", value: walk.distanceMeters.kilometres)
                LabeledContent("Čas", value: "\(walk.start.formatted(date: .omitted, time: .shortened))–\(walk.end.formatted(date: .omitted, time: .shortened))")
                LabeledContent("Kde", value: walk.place)
                if walk.segments.count > 1 {
                    LabeledContent("Výpadky GPS", value: "\(walk.segments.count - 1)")
                }
            }
            if !walk.streets.isEmpty {
                Section("Ulice (\(walk.streets.count))") {
                    ForEach(walk.streets, id: \.self) { Text($0) }
                }
            }
        }
        .navigationTitle(walk.start.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One walk on its own map, each GPS segment as its own line so a gap is
/// never drawn through houses.
struct WalkMapView: UIViewRepresentable {
    let walk: Walk
    var color: UIColor = .systemOrange

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        context.coordinator.color = color
        var rect = MKMapRect.null
        for segment in walk.segments where segment.count >= 2 {
            let coords = segment.map { CLLocationCoordinate2D(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
            let line = MKPolyline(coordinates: coords, count: coords.count)
            map.addOverlay(line)
            rect = rect.union(line.boundingMapRect)
        }
        if !rect.isNull {
            map.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 30, left: 30, bottom: 30, right: 30), animated: false)
        }
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var color: UIColor = .systemOrange
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            let renderer = MKPolylineRenderer(overlay: overlay)
            renderer.strokeColor = color
            renderer.lineWidth = 4
            return renderer
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

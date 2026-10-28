import SwiftUI
import MapKit
import StreetTrackerCore

/// A walk the phone didn't record (flat battery, GPS off): pick when it
/// started and draw it with a finger; in Prague the line snaps to streets.
struct NewDrawnWalkView: View {
    @EnvironmentObject private var viewModel: TrackingViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var start = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
    @State private var strokes: [[Coordinate]] = []
    @State private var drawing = true

    /// Old Town Square when there's no recent location.
    private static let prague = Coordinate(latitude: 50.0875, longitude: 14.4213)

    private var lines: [WalkMapView.Line] {
        strokes.enumerated().map { i, stroke in
            WalkMapView.Line(id: "ruka-\(i)", points: stroke, color: .systemOrange, width: 5)
        }
    }

    private var lengthKm: Double { DrawnWalk.length(of: strokes) / 1000 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                WalkMapView(lines: lines, drawing: drawing, center: viewModel.lastLocation ?? Self.prague,
                            snap: { [matcher = viewModel.streetMatcher] in matcher?.snap($0) ?? $0 }) { stroke in
                    strokes.append(stroke)
                }
                Form {
                    DatePicker("Začátek", selection: $start, in: ...Date().addingTimeInterval(-DrawnWalk.duration(of: strokes)))
                    Picker("Prst", selection: $drawing) {
                        Text("Kreslí").tag(true)
                        Text("Posouvá mapu").tag(false)
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        Text(String(format: "%.2f km · asi %.0f min", lengthKm, DrawnWalk.duration(of: strokes) / 60))
                            .monospacedDigit()
                        Spacer()
                        Button("Vrátit tah") { strokes.removeLast() }
                            .disabled(strokes.isEmpty)
                    }
                    Text("Kresli jedním prstem, dvěma posouváš mapu. V Praze se čára přichytí k ulicím.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(height: 260)
            }
            .navigationTitle("Nová procházka ručně")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zrušit") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Uložit") {
                        viewModel.addDrawnWalk(strokes: strokes, start: start)
                        dismiss()
                    }
                    .disabled(lengthKm == 0)
                }
            }
        }
    }
}

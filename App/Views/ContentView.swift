import SwiftUI
import CoreLocation

struct ContentView: View {
    @StateObject private var viewModel = TrackingViewModel()
    @State private var showingSuggestions = false

    var body: some View {
        ZStack(alignment: .bottom) {
            MapView(graph: viewModel.graph, passCounts: viewModel.passCounts)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(Int(viewModel.coverageFraction * 100))% of loaded streets walked")
                        .font(.headline)
                    Spacer()
                    Button(viewModel.isTracking ? "Stop" : "Start") {
                        viewModel.toggleTracking()
                    }
                    .buttonStyle(.borderedProminent)
                }

                if viewModel.isLoadingStreets {
                    ProgressView("Loading Prague streets…")
                        .font(.caption)
                }

                if viewModel.authorizationStatus == .denied || viewModel.authorizationStatus == .restricted {
                    Text("Background location is off. Enable \"Always\" in Settings to track while the app isn't in the foreground.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let leastComplete = topDistricts.first {
                    Text("Least walked: \(leastComplete.name) (\(Int(leastComplete.fraction * 100))%)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Suggest nearby streets") {
                    viewModel.refreshSuggestions()
                    showingSuggestions = true
                }
                .disabled(viewModel.lastLocation == nil)
                .font(.caption)
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding()
        }
        .onAppear {
            viewModel.requestPermission()
        }
        .sheet(isPresented: $showingSuggestions) {
            SuggestionsView(suggestions: viewModel.suggestions)
        }
    }

    private var topDistricts: [(name: String, fraction: Double)] {
        viewModel.districtCoverage
            .filter { $0.value < 1.0 }
            .sorted { $0.value < $1.value }
            .prefix(1)
            .map { (name: $0.key, fraction: $0.value) }
    }
}

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
                    Text(verbatim: "Prošlo \((viewModel.coverageFraction * 100).formatted(.number.precision(.fractionLength(1)))) % ulic Prahy")
                        .font(.headline)
                    Spacer()
                    Button(viewModel.isTracking ? "Zastavit" : "Začít") {
                        viewModel.toggleTracking()
                    }
                    .buttonStyle(.borderedProminent)
                }

                if viewModel.isTracking {
                    Text(verbatim: "Nahrávám trasu · \(viewModel.loggedPoints) bodů (Soubory › Prague Streets › trasy)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if viewModel.isLoadingStreets {
                    ProgressView("Načítám ulice Prahy…")
                        .font(.caption)
                }

                if viewModel.authorizationStatus == .denied || viewModel.authorizationStatus == .restricted {
                    Text("Poloha je vypnutá. V Nastavení povol „Vždy“, aby appka sledovala chůzi i se zamčeným telefonem.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let leastComplete = topDistricts.first {
                    Text(verbatim: "Nejméně prošlá čtvrť: \(leastComplete.name) (\(Int(leastComplete.fraction * 100)) %)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Navrhni neprošlé ulice poblíž") {
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
            // "Unknown" = the few streets outside every district polygon.
            .filter { $0.key != "Unknown" && $0.value < 1.0 }
            .sorted { $0.value < $1.value }
            .prefix(1)
            .map { (name: $0.key, fraction: $0.value) }
    }
}

import SwiftUI
import CoreLocation
import StreetTrackerCore

struct ContentView: View {
    @EnvironmentObject private var viewModel: TrackingViewModel
    @State private var showingSuggestions = false
    @State private var showingWalks = false
    @State private var showingData = false
    @State private var showingStats = false
    /// Long-pressed street, asking "prošel jsem ji?".
    @State private var pressedStreet: StreetSegment?

    var body: some View {
        ZStack(alignment: .bottom) {
            MapView(graph: viewModel.graph, passCounts: viewModel.passCounts, pieces: viewModel.mapPieces, route: viewModel.todaysRoute,
                    centerOnRoute: viewModel.isDemo,
                    onLongPress: { pressedStreet = viewModel.street(near: $0) })
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    // Two decimals below 1 %, so the first walks show progress.
                    Text(verbatim: "Prošlo \((viewModel.coverageFraction * 100).formatted(.number.precision(.fractionLength(viewModel.coverageFraction < 0.01 ? 2 : 1)))) % ulic Prahy")
                        .font(.headline)
                        .accessibilityIdentifier("pokryti")
                    Spacer()
                    Button(viewModel.isTracking ? "Zastavit" : "Začít") {
                        viewModel.toggleTracking()
                    }
                    .buttonStyle(.borderedProminent)
                }

                Picker("Režim", selection: $viewModel.mode) {
                    Text("Přesný").tag(PowerPolicy.Mode.precise)
                    Text("Úsporný").tag(PowerPolicy.Mode.saving)
                }
                .pickerStyle(.segmented)

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

                HStack {
                    Button("Navrhni neprošlé ulice poblíž") {
                        viewModel.refreshSuggestions()
                        showingSuggestions = true
                    }
                    .disabled(viewModel.lastLocation == nil)
                    Spacer()
                    Button("Přehledy") { showingStats = true }
                    Button("Procházky") { showingWalks = true }
                    Button("Data") { showingData = true }
                }
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
        .sheet(isPresented: $showingWalks) {
            WalksView().environmentObject(viewModel)
        }
        .sheet(isPresented: $showingStats) {
            StatsView().environmentObject(viewModel)
        }
        .sheet(isPresented: $showingData) {
            DataView().environmentObject(viewModel)
        }
        .confirmationDialog(
            pressedStreet?.name ?? "Ulice bez jména",
            isPresented: Binding(get: { pressedStreet != nil }, set: { if !$0 { pressedStreet = nil } }),
            titleVisibility: .visible,
            presenting: pressedStreet
        ) { street in
            if viewModel.manualStreets.contains(street.id) {
                Button("Zrušit ruční označení") { viewModel.toggleManual(street.id) }
            } else if viewModel.passCounts[street.id, default: 0] == 0 {
                Button("Tenhle úsek jsem prošel") { viewModel.toggleManual(street.id) }
            }
        } message: { street in
            let n = viewModel.passCounts[street.id, default: 0]
            Text(n == 0 ? "Zatím neprošlá." : "Prošlá \(n)×" + (viewModel.manualStreets.contains(street.id) ? " (označeno ručně)" : ""))
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

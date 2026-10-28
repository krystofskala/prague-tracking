import SwiftUI
import UniformTypeIdentifiers

/// Obsidian folder, backup and restore, GPX import.
struct DataView: View {
    @EnvironmentObject private var viewModel: TrackingViewModel
    @State private var picking: Picking?

    private enum Picking: Identifiable {
        case obsidian, restore, gpx
        var id: Self { self }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let name = viewModel.obsidianFolderName {
                        LabeledContent("Složka", value: name)
                        Button("Zapsat procházky teď") { viewModel.syncWalks() }
                        Button("Změnit složku") { picking = .obsidian }
                        Button("Přestat zapisovat", role: .destructive) { viewModel.forgetObsidianFolder() }
                    } else {
                        Button("Vybrat složku v trezoru") { picking = .obsidian }
                    }
                } header: {
                    Text("Obsidian")
                } footer: {
                    Text("Každá procházka se zapíše jako poznámka a GPX (soubory › Na mém iPhonu › Obsidian › tvůj trezor). Co napíšeš pod „Moje poznámky“, appka nikdy nepřepíše.")
                }

                Section {
                    Button("Zálohovat do složky Obsidianu") { viewModel.backup() }
                        .disabled(viewModel.obsidianFolderName == nil)
                    Button("Obnovit ze zálohy…") { picking = .restore }
                } header: {
                    Text("Záloha")
                } footer: {
                    Text("Záloha = pokrytí ulic, všechny trasy a názvy procházek ve složce zaloha. Obnova nic neztratí: u ulic platí vyšší počet průchodů.")
                }

                Section {
                    Button("Importovat GPX…") { picking = .gpx }
                } header: {
                    Text("Import")
                } footer: {
                    Text("Trasy ze Stravy, Garminu nebo jiné appky. Pražské ulice se započítají.")
                }

                Section {
                    Button(viewModel.isRebuilding ? "Přepočítávám…" : "Přepočítat historii") { viewModel.rebuildCoverage() }
                        .disabled(viewModel.isRebuilding || viewModel.isLoadingStreets)
                } header: {
                    Text("Pokrytí")
                } footer: {
                    Text("Projde znovu všechny uložené body (od 26. 10.) podle nejnovějších pravidel. Úpravy procházek a ručně označené ulice zůstanou.")
                }

                if let status = viewModel.dataStatus {
                    Section { Text(status).font(.footnote) }
                }
            }
            .navigationTitle("Data")
            .fileImporter(isPresented: Binding(get: { picking != nil }, set: { if !$0 { picking = nil } }),
                          allowedContentTypes: picking == .gpx ? [UTType(filenameExtension: "gpx") ?? .xml, .xml] : [.folder]) { result in
                guard case let .success(url) = result else { return }
                switch picking {
                case .obsidian: viewModel.chooseObsidianFolder(url)
                case .restore: viewModel.restore(from: url)
                case .gpx: viewModel.importGPX(url)
                case nil: break
                }
                picking = nil
            }
        }
    }
}

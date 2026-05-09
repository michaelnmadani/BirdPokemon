import SwiftUI

/// The full species catalog. Also usable as a species picker when presented
/// in "picker mode" from the capture flow.
struct CatalogView: View {
    struct PickerConfig: Identifiable {
        let id = UUID()
        let onSelect: (Species) -> Void
    }

    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = CatalogViewModel()
    @StateObject private var filterState = FilterState()

    let picker: PickerConfig?

    init(picker: PickerConfig? = nil) {
        self.picker = picker
    }

    var body: some View {
        if picker == nil {
            NavigationStack { catalogContent }
        } else {
            catalogContent
        }
    }

    @ViewBuilder
    private var catalogContent: some View {
        VStack(spacing: 0) {
            FilterBarView(state: filterState)
                .padding(.vertical, 6)
            List(viewModel.filtered(by: filterState.criteria)) { species in
                if let picker {
                    Button {
                        picker.onSelect(species)
                    } label: {
                        SpeciesRowView(
                            species: species,
                            isCaptured: isCaptured(species)
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    NavigationLink(value: species) {
                        SpeciesRowView(
                            species: species,
                            isCaptured: isCaptured(species)
                        )
                    }
                }
            }
            .listStyle(.plain)
        }
        .searchable(text: $filterState.criteria.searchText, prompt: "Search species")
        .navigationTitle(picker == nil ? "Catalog" : "Pick a species")
        .navigationDestination(for: Species.self) { species in
            SpeciesDetailView(species: species)
        }
        .sheet(isPresented: $filterState.showFilterSheet) {
            FilterSheetView(state: filterState,
                            availableFamilies: viewModel.availableFamilies)
        }
        .task {
            await viewModel.load(region: appState.selectedRegion)
        }
        .onChange(of: appState.selectedRegion) { _, newRegion in
            Task { await viewModel.load(region: newRegion) }
        }
        .overlay {
            if viewModel.isLoading && viewModel.allSpecies.isEmpty {
                LoadingView(message: "Loading catalog…")
            } else if viewModel.allSpecies.isEmpty {
                EmptyStateView(
                    title: "No species yet",
                    message: "Run the seed script or connect to the internet to populate the catalog."
                )
            }
        }
    }

    private func isCaptured(_ species: Species) -> Bool {
        appState.currentUser?.capturedSpeciesCodes.contains(species.ebirdCode) ?? false
    }
}

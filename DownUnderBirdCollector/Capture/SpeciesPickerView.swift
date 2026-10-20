import SwiftUI

/// Searchable species list used to choose what was photographed.
struct SpeciesPickerView: View {
    let region: Region
    let onSelect: (Species) -> Void

    @EnvironmentObject private var catalog: SpeciesCatalog
    @EnvironmentObject private var store: SightingStore
    @State private var searchText = ""

    private var results: [Species] {
        var criteria = FilterCriteria()
        criteria.searchText = searchText
        return catalog.species(in: region).filter(criteria.matches)
    }

    var body: some View {
        List(results) { species in
            Button {
                onSelect(species)
            } label: {
                SpeciesRowView(species: species, isCaptured: store.isCaptured(species))
            }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search by name or family")
        .navigationTitle("Choose species")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if results.isEmpty {
                EmptyStateView(
                    systemImage: "magnifyingglass",
                    title: "No matches",
                    message: "Try a shorter name, or the bird's family (e.g. \"honeyeater\")."
                )
            }
        }
    }
}

import SwiftUI

/// The field guide: every species in the selected region, searchable and
/// filterable by size, colour and family.
struct CatalogView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var catalog: SpeciesCatalog
    @EnvironmentObject private var store: SightingStore
    @StateObject private var filterState = FilterState()

    private var regionSpecies: [Species] {
        catalog.species(in: appState.selectedRegion)
    }

    private var results: [Species] {
        regionSpecies.filter(filterState.criteria.matches)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                FilterBarView(state: filterState, resultCount: results.count)
                    .padding(.vertical, 6)
                List(results) { species in
                    NavigationLink(value: species) {
                        SpeciesRowView(species: species, isCaptured: store.isCaptured(species))
                    }
                }
                .listStyle(.plain)
            }
            .searchable(text: $filterState.criteria.searchText, prompt: "Search species")
            .navigationTitle("Field Guide")
            .navigationDestination(for: Species.self) { species in
                SpeciesDetailView(species: species)
            }
            .sheet(isPresented: $filterState.showFilterSheet) {
                FilterSheetView(state: filterState, availableFamilies: families)
            }
            .overlay {
                if regionSpecies.isEmpty {
                    EmptyStateView(
                        title: "No species yet",
                        message: "There's no species list for \(appState.selectedRegion.displayName) in this version."
                    )
                } else if results.isEmpty {
                    EmptyStateView(
                        systemImage: "line.3.horizontal.decrease.circle",
                        title: "No matches",
                        message: "Try removing a filter."
                    )
                }
            }
        }
    }

    private var families: [FamilyOption] {
        FamilyOption.options(for: regionSpecies)
    }
}

/// A family filter choice: scientific name as the key, common name for display.
struct FamilyOption: Identifiable, Hashable {
    let family: String
    let displayName: String
    var id: String { family }

    static func options(for species: [Species]) -> [FamilyOption] {
        var seen: [String: String] = [:]
        for s in species where seen[s.family] == nil {
            seen[s.family] = s.familyDisplayName
        }
        return seen.map { FamilyOption(family: $0.key, displayName: $0.value) }
            .sorted { $0.displayName < $1.displayName }
    }
}

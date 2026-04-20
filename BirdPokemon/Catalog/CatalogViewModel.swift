import Foundation

@MainActor
final class CatalogViewModel: ObservableObject {
    @Published private(set) var allSpecies: [Species] = []
    @Published private(set) var isLoading: Bool = false

    private let repo = SpeciesRepository.shared

    func load(region: Region) async {
        isLoading = true
        defer { isLoading = false }
        let list = await repo.speciesList(region: region)
        allSpecies = list
    }

    func filtered(by criteria: FilterCriteria) -> [Species] {
        allSpecies.filter(criteria.matches)
    }

    var availableFamilies: [String] {
        Array(Set(allSpecies.map(\.family))).sorted()
    }
}

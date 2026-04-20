import Foundation

@MainActor
final class CollectionViewModel: ObservableObject {
    @Published private(set) var regionSpecies: [Species] = []
    @Published private(set) var isLoading: Bool = false

    private let repo = SpeciesRepository.shared

    func load(region: Region) async {
        isLoading = true
        defer { isLoading = false }
        regionSpecies = await repo.speciesList(region: region)
    }

    func entries(filters: FilterCriteria) -> [Species] {
        regionSpecies.filter(filters.matches)
    }

    func progress(captured: Set<String>) -> (have: Int, total: Int) {
        let have = regionSpecies.filter { captured.contains($0.ebirdCode) }.count
        return (have, regionSpecies.count)
    }
}

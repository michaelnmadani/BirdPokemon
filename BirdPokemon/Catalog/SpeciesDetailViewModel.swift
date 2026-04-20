import Foundation

@MainActor
final class SpeciesDetailViewModel: ObservableObject {
    @Published private(set) var sightings: [Sighting] = []
    @Published private(set) var isLoading: Bool = false

    private let sightingsRepo = SightingsRepository()

    func load(uid: String, speciesCode: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            sightings = try await sightingsRepo.listForUser(uid: uid, speciesCode: speciesCode)
        } catch {
            print("SpeciesDetail: load failed — \(error)")
            sightings = []
        }
    }
}

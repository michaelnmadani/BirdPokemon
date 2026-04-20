import Foundation

@MainActor
final class SightingsListViewModel: ObservableObject {
    @Published private(set) var sightings: [Sighting] = []
    @Published private(set) var isLoading: Bool = false
    @Published var errorMessage: String?

    private let repo = SightingsRepository()
    private var streamTask: Task<Void, Never>?

    deinit { streamTask?.cancel() }

    func start(uid: String) {
        streamTask?.cancel()
        isLoading = true
        streamTask = Task {
            do {
                for try await sightings in repo.stream(uid: uid) {
                    self.sightings = sightings
                    self.isLoading = false
                }
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    func delete(_ sighting: Sighting) async {
        guard let id = sighting.documentID else { return }
        do {
            try await repo.delete(sightingId: id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

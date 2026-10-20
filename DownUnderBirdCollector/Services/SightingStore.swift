import Foundation
import UIKit

/// Where sightings actually live: a folder on the device, or Firestore.
@MainActor
protocol SightingBackend: AnyObject {
    /// Begin delivering the full sightings list, now and on every change.
    func start(onUpdate: @escaping @MainActor (Result<[Sighting], Error>) -> Void)
    func stop()
    func add(_ draft: SightingDraft, photo: ProcessedPhoto?) async throws -> Sighting
    func delete(_ sighting: Sighting) async throws
    func photoURL(for sighting: Sighting) -> URL?
    func thumbnailURL(for sighting: Sighting) -> URL?
}

/// The user's sightings, whichever backend holds them. Everything "caught"
/// in the app is derived from this list, so the collection updates the
/// moment a sighting is saved or deleted.
@MainActor
final class SightingStore: ObservableObject {
    @Published private(set) var sightings: [Sighting] = [] {
        didSet { rebuildIndex() }
    }
    @Published private(set) var isLoading = false
    @Published var lastError: String?

    /// eBird codes of every species with at least one sighting.
    private(set) var capturedCodes: Set<String> = []
    private var latestByCode: [String: Sighting] = [:]

    private var backend: SightingBackend?

    init(backend: SightingBackend? = nil) {
        attach(backend)
    }

    func attach(_ newBackend: SightingBackend?) {
        backend?.stop()
        backend = newBackend
        sightings = []
        lastError = nil
        guard let newBackend else {
            isLoading = false
            return
        }
        isLoading = true
        newBackend.start { [weak self, weak newBackend] result in
            guard let self, let newBackend, newBackend === self.backend else { return }
            self.isLoading = false
            switch result {
            case .success(let list):
                self.sightings = list.sorted { $0.capturedAt > $1.capturedAt }
            case .failure(let error):
                self.lastError = error.localizedDescription
            }
        }
    }

    func isCaptured(_ species: Species) -> Bool {
        capturedCodes.contains(species.ebirdCode)
    }

    func latestSighting(of speciesCode: String) -> Sighting? {
        latestByCode[speciesCode]
    }

    func sightings(of speciesCode: String) -> [Sighting] {
        sightings.filter { $0.speciesCode == speciesCode }
    }

    @discardableResult
    func add(_ draft: SightingDraft) async throws -> Sighting {
        guard let backend else { throw StoreError.notReady }
        var processed: ProcessedPhoto?
        if let image = draft.photo?.image {
            processed = try await Task.detached(priority: .userInitiated) {
                try ImageProcessing.process(image)
            }.value
        }
        do {
            return try await backend.add(draft, photo: processed)
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    func delete(ids: [String]) async {
        guard let backend else { return }
        let targets = sightings.filter { ids.contains($0.id) }
        for sighting in targets {
            do {
                try await backend.delete(sighting)
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func deleteAll() async throws {
        guard let backend else { return }
        for sighting in sightings {
            try await backend.delete(sighting)
        }
    }

    func photoURL(for sighting: Sighting) -> URL? {
        backend?.photoURL(for: sighting)
    }

    func thumbnailURL(for sighting: Sighting) -> URL? {
        backend?.thumbnailURL(for: sighting)
    }

    private func rebuildIndex() {
        capturedCodes = Set(sightings.map(\.speciesCode))
        var latest: [String: Sighting] = [:]
        for sighting in sightings {
            if let existing = latest[sighting.speciesCode], existing.capturedAt >= sighting.capturedAt { continue }
            latest[sighting.speciesCode] = sighting
        }
        latestByCode = latest
    }

    enum StoreError: LocalizedError {
        case notReady

        var errorDescription: String? { "Your sightings aren't available yet. Try again in a moment." }
    }
}

import Foundation
import FirebaseFirestore
import FirebaseStorage

/// Cloud backend: one Firestore document per sighting in `sightings/`, photos
/// in Storage under `users/<uid>/sightings/`. Firestore's offline cache keeps
/// the list available without a connection.
@MainActor
final class FirebaseSightingBackend: SightingBackend {
    let uid: String
    private var listener: ListenerRegistration?

    private var collection: CollectionReference {
        Firestore.firestore().collection("sightings")
    }

    init(uid: String) {
        self.uid = uid
    }

    func start(onUpdate: @escaping @MainActor (Result<[Sighting], Error>) -> Void) {
        listener?.remove()
        // No orderBy: sorting happens client-side, so no composite index is needed.
        listener = collection
            .whereField("userId", isEqualTo: uid)
            .addSnapshotListener { snapshot, error in
                let result: Result<[Sighting], Error>
                if let error {
                    result = .failure(error)
                } else {
                    let list = snapshot?.documents.compactMap { try? $0.data(as: Sighting.self) } ?? []
                    result = .success(list)
                }
                // Firestore delivers snapshot callbacks on the main queue.
                MainActor.assumeIsolated { onUpdate(result) }
            }
    }

    func stop() {
        listener?.remove()
        listener = nil
    }

    func add(_ draft: SightingDraft, photo: ProcessedPhoto) async throws -> Sighting {
        let document = collection.document()
        let id = document.documentID
        let photoPath = "users/\(uid)/sightings/\(id).jpg"
        let thumbnailPath = "users/\(uid)/sightings/\(id)_thumb.jpg"
        let storage = Storage.storage()

        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        let photoRef = storage.reference(withPath: photoPath)
        let thumbnailRef = storage.reference(withPath: thumbnailPath)
        _ = try await photoRef.putDataAsync(photo.full, metadata: metadata)
        _ = try await thumbnailRef.putDataAsync(photo.thumbnail, metadata: metadata)
        let photoURL = try await photoRef.downloadURL()
        let thumbnailURL = try await thumbnailRef.downloadURL()

        let sighting = Sighting(
            id: id,
            userId: uid,
            speciesCode: draft.species.ebirdCode,
            speciesCommonName: draft.species.commonName,
            speciesSciName: draft.species.scientificName,
            capturedAt: draft.capturedAt,
            createdAt: Date(),
            latitude: draft.coordinate?.latitude,
            longitude: draft.coordinate?.longitude,
            locationAccuracy: draft.locationAccuracy,
            locationSource: draft.locationSource,
            notes: draft.notes,
            mlTopPrediction: draft.mlTopPrediction?.speciesCode,
            mlTopConfidence: draft.mlTopPrediction?.confidence,
            userOverrode: draft.userOverrode,
            photoURL: photoURL.absoluteString,
            thumbnailURL: thumbnailURL.absoluteString,
            photoStoragePath: photoPath,
            thumbnailStoragePath: thumbnailPath
        )

        do {
            try document.setData(from: sighting)
        } catch {
            try? await photoRef.delete()
            try? await thumbnailRef.delete()
            throw error
        }
        return sighting
    }

    func delete(_ sighting: Sighting) async throws {
        try await collection.document(sighting.id).delete()
        let storage = Storage.storage()
        for path in [sighting.photoStoragePath, sighting.thumbnailStoragePath].compactMap({ $0 }) {
            try? await storage.reference(withPath: path).delete()
        }
    }

    func photoURL(for sighting: Sighting) -> URL? {
        sighting.photoURL.flatMap(URL.init(string:))
    }

    func thumbnailURL(for sighting: Sighting) -> URL? {
        (sighting.thumbnailURL ?? sighting.photoURL).flatMap(URL.init(string:))
    }
}

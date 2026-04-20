import Foundation
import FirebaseFirestore
import Combine

struct SightingsRepository {
    private var collection: CollectionReference {
        FirebaseService.firestore.collection(FirebaseService.Collection.sightings)
    }

    func create(_ sighting: Sighting) async throws -> String {
        let ref = collection.document()
        var value = sighting
        value.documentID = ref.documentID
        try ref.setData(from: value)
        return ref.documentID
    }

    func delete(sightingId: String) async throws {
        try await collection.document(sightingId).delete()
    }

    func listForUser(uid: String, limit: Int = 100) async throws -> [Sighting] {
        let snap = try await collection
            .whereField("userId", isEqualTo: uid)
            .order(by: "capturedAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        return snap.documents.compactMap { try? $0.data(as: Sighting.self) }
    }

    func listForUser(uid: String, speciesCode: String) async throws -> [Sighting] {
        let snap = try await collection
            .whereField("userId", isEqualTo: uid)
            .whereField("speciesCode", isEqualTo: speciesCode)
            .order(by: "capturedAt", descending: true)
            .getDocuments()
        return snap.documents.compactMap { try? $0.data(as: Sighting.self) }
    }

    /// Live-updating stream of the user's sightings.
    func stream(uid: String) -> AsyncThrowingStream<[Sighting], Error> {
        AsyncThrowingStream { continuation in
            let listener = collection
                .whereField("userId", isEqualTo: uid)
                .order(by: "capturedAt", descending: true)
                .addSnapshotListener { snap, error in
                    if let error {
                        continuation.finish(throwing: error)
                        return
                    }
                    let sightings = snap?.documents.compactMap { try? $0.data(as: Sighting.self) } ?? []
                    continuation.yield(sightings)
                }
            continuation.onTermination = { _ in listener.remove() }
        }
    }
}

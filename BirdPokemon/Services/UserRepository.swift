import Foundation
import FirebaseFirestore

struct UserRepository {
    private var collection: CollectionReference {
        FirebaseService.firestore.collection(FirebaseService.Collection.users)
    }

    func fetch(uid: String) async throws -> AppUser? {
        let snapshot = try await collection.document(uid).getDocument()
        guard snapshot.exists else { return nil }
        return try snapshot.data(as: AppUser.self)
    }

    /// Reads the user doc or creates it on first sign-in.
    func ensureUser(uid: String, displayName: String?, email: String?) async throws -> AppUser {
        if let existing = try await fetch(uid: uid) {
            try await collection.document(uid).updateData([
                "lastActiveAt": FieldValue.serverTimestamp()
            ])
            return existing
        }
        let user = AppUser.new(uid: uid, displayName: displayName, email: email)
        try collection.document(uid).setData(from: user, merge: true)
        return user
    }

    func updateHomeRegion(uid: String, region: Region) async throws {
        try await collection.document(uid).updateData([
            "homeRegionCode": region.rawValue
        ])
    }

    func addCapturedSpecies(uid: String, speciesCode: String) async throws {
        try await collection.document(uid).updateData([
            "capturedSpeciesCodes": FieldValue.arrayUnion([speciesCode]),
            "capturedCount": FieldValue.increment(Int64(1)),
            "lastActiveAt": FieldValue.serverTimestamp()
        ])
    }
}

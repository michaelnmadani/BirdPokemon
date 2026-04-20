import Foundation
import FirebaseFirestore
import FirebaseStorage
import FirebaseAuth

enum FirebaseService {
    static var firestore: Firestore { Firestore.firestore() }
    static var storage: Storage { Storage.storage() }
    static var auth: Auth { Auth.auth() }

    enum Collection {
        static let users = "users"
        static let sightings = "sightings"
        static let speciesCache = "speciesCache"
    }
}

import Foundation
import FirebaseFirestore

struct AppUser: Identifiable, Codable, Hashable {
    @DocumentID var documentID: String?

    let uid: String
    var displayName: String?
    var email: String?
    var photoURL: String?
    var homeRegionCode: String?
    var capturedSpeciesCodes: [String]
    var capturedCount: Int

    @ServerTimestamp var createdAt: Date?
    var lastActiveAt: Date?

    var id: String { uid }

    var homeRegion: Region? {
        guard let code = homeRegionCode else { return nil }
        return Region(rawValue: code)
    }

    static func new(uid: String, displayName: String?, email: String?) -> AppUser {
        AppUser(
            documentID: uid,
            uid: uid,
            displayName: displayName,
            email: email,
            photoURL: nil,
            homeRegionCode: Region.australia.rawValue,
            capturedSpeciesCodes: [],
            capturedCount: 0,
            createdAt: nil,
            lastActiveAt: Date()
        )
    }
}

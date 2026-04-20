import Foundation
import FirebaseFirestore

struct Species: Identifiable, Codable, Hashable {
    @DocumentID var documentID: String?

    let ebirdCode: String
    let commonName: String
    let scientificName: String
    let order: String
    let family: String
    let familyCommonName: String?
    let category: String            // eBird category: "species" | "issf" | "slash" | ...

    let sizeCategory: SizeCategory
    let primaryColors: [BirdColor]
    let regionCodes: [String]       // e.g. ["AU", "NZ"]

    let thumbnailURL: String?
    let wikipediaURL: String?
    let ebirdURL: String

    let updatedAt: Date?

    var id: String { ebirdCode }

    var regions: [Region] {
        regionCodes.compactMap { Region(rawValue: $0) }
    }

    enum CodingKeys: String, CodingKey {
        case documentID
        case ebirdCode
        case commonName
        case scientificName
        case order
        case family
        case familyCommonName
        case category
        case sizeCategory
        case primaryColors
        case regionCodes
        case thumbnailURL
        case wikipediaURL
        case ebirdURL
        case updatedAt
    }
}

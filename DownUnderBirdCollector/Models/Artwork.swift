import Foundation

/// Field guide pictures can be the iNaturalist photo or a watercolour painted
/// from it (by scripts/artwork/watercolour.py).
enum PictureStyle: String, CaseIterable, Identifiable {
    case watercolour, photo

    var id: String { rawValue }
    var label: String { self == .watercolour ? "Watercolour" : "Photo" }
}

/// One watercolour, as recorded in `Art/art_<REGION>.json`. The painting is an
/// adaptation of the credited photo and keeps its licence.
struct Artwork: Decodable, Equatable {
    let file: String
    var photoAttribution: String?
    var photoLicense: String?
    var license: String?

    /// "Watercolour after a photo by © Jane Doe · CC BY-NC via iNaturalist"
    var credit: String {
        let photo = [photoAttribution, photoLicense.map(Species.licenceLabel)].compactMap { $0 }.joined(separator: " · ")
        return "Watercolour after a photo\(photo.isEmpty ? "" : " by \(photo)") via iNaturalist"
    }
}

struct ArtManifest: Decodable {
    var species: [String: Artwork]

    /// Lenient: one bad entry is skipped instead of losing every painting.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decodeIfPresent([String: FailableArtwork].self, forKey: .species) ?? [:]
        species = raw.compactMapValues(\.value)
    }

    private enum CodingKeys: String, CodingKey { case species }

    private struct FailableArtwork: Decodable {
        let value: Artwork?
        init(from decoder: Decoder) throws { value = try? Artwork(from: decoder) }
    }
}

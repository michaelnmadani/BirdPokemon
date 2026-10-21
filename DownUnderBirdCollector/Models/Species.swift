import Foundation

/// One species record from the bundled `taxonomy_<REGION>.json`.
struct Species: Identifiable, Hashable {
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
    let thumbnailAttribution: String?
    let thumbnailLicense: String?
    /// A recording of its call or song ("Hear its call").
    var callURL: String? = nil
    var callAttribution: String? = nil
    var callLicense: String? = nil
    var callSource: String? = nil
    var callPageURL: String? = nil
    let wikipediaURL: String?
    let ebirdURL: String

    var id: String { ebirdCode }

    var regions: [Region] {
        regionCodes.compactMap { Region(rawValue: $0) }
    }

    var familyDisplayName: String { familyCommonName ?? family }

    var thumbnail: URL? { thumbnailURL.flatMap(URL.init(string:)) }

    /// "© Jane Doe, CC BY-NC" style credit line for the thumbnail, if known.
    var photoCredit: String? {
        let parts = [thumbnailAttribution, thumbnailLicense.map(Self.licenceLabel)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var call: URL? { callURL.flatMap(URL.init(string:)) }

    /// "© Jane Doe · CC BY-NC via xeno-canto"
    var callCredit: String? {
        guard callURL != nil else { return nil }
        let source = ["xeno-canto": "xeno-canto", "inaturalist": "iNaturalist"][callSource ?? ""] ?? "the web"
        let parts = [callAttribution, callLicense.map(Self.licenceLabel)].compactMap { $0 }
        return "\(parts.isEmpty ? "Recording" : parts.joined(separator: " · ")) via \(source)"
    }

    /// "cc-by-nc" -> "CC BY-NC", "cc0" -> "CC0".
    static func licenceLabel(_ code: String) -> String {
        code.uppercased().replacingOccurrences(of: "CC-", with: "CC ")
    }
}

extension Species: Decodable {
    enum CodingKeys: String, CodingKey {
        case ebirdCode, commonName, scientificName, order, family, familyCommonName, category
        case sizeCategory, primaryColors, regionCodes
        case thumbnailURL, thumbnailAttribution, thumbnailLicense, wikipediaURL, ebirdURL
        case callURL, callAttribution, callLicense, callSource, callPageURL
    }

    /// Lenient on everything except identity: unknown colours are folded or
    /// dropped and unknown sizes fall back to `.medium`, so one odd value in
    /// the data can never empty the catalog.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ebirdCode = try c.decode(String.self, forKey: .ebirdCode)
        commonName = try c.decode(String.self, forKey: .commonName)
        scientificName = try c.decode(String.self, forKey: .scientificName)
        order = try c.decodeIfPresent(String.self, forKey: .order) ?? ""
        family = try c.decodeIfPresent(String.self, forKey: .family) ?? "Unknown"
        familyCommonName = try c.decodeIfPresent(String.self, forKey: .familyCommonName)
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? "species"

        let size = try c.decodeIfPresent(String.self, forKey: .sizeCategory)
        sizeCategory = size.flatMap(SizeCategory.init(rawValue:)) ?? .medium

        var colors: [BirdColor] = []
        for raw in try c.decodeIfPresent([String].self, forKey: .primaryColors) ?? [] {
            if let color = BirdColor(lenient: raw), !colors.contains(color) {
                colors.append(color)
            }
        }
        primaryColors = colors

        regionCodes = try c.decodeIfPresent([String].self, forKey: .regionCodes) ?? []
        thumbnailURL = try c.decodeIfPresent(String.self, forKey: .thumbnailURL)
        thumbnailAttribution = try c.decodeIfPresent(String.self, forKey: .thumbnailAttribution)
        thumbnailLicense = try c.decodeIfPresent(String.self, forKey: .thumbnailLicense)
        callURL = try c.decodeIfPresent(String.self, forKey: .callURL)
        callAttribution = try c.decodeIfPresent(String.self, forKey: .callAttribution)
        callLicense = try c.decodeIfPresent(String.self, forKey: .callLicense)
        callSource = try c.decodeIfPresent(String.self, forKey: .callSource)
        callPageURL = try c.decodeIfPresent(String.self, forKey: .callPageURL)
        wikipediaURL = try c.decodeIfPresent(String.self, forKey: .wikipediaURL)
        ebirdURL = try c.decodeIfPresent(String.self, forKey: .ebirdURL)
            ?? "https://ebird.org/species/\(ebirdCode)"
    }
}

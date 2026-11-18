import Foundation
import os

/// The species list, loaded once from the bundled `taxonomy_<REGION>.json`
/// files. Works fully offline; this is the app's only source of species data.
@MainActor
final class SpeciesCatalog: ObservableObject {
    private(set) var byRegion: [Region: [Species]] = [:]
    private(set) var byCode: [String: Species] = [:]
    /// Human-readable problems found while loading (shown in Settings).
    private(set) var loadIssues: [String] = []
    private var groupsByRegion: [Region: (groups: [SpeciesGroup], byCode: [String: [SpeciesGroup]])] = [:]
    /// Watercolours by species code, with the file each one is in.
    private(set) var artwork: [String: (art: Artwork, url: URL)] = [:]
    /// Watercolour or photo for field guide pictures; remembered between launches.
    @Published var pictureStyle: PictureStyle {
        didSet { UserDefaults.standard.set(pictureStyle.rawValue, forKey: Self.pictureStyleKey) }
    }
    static let pictureStyleKey = "pictures"

    private static let log = Logger(subsystem: "DownUnderBirdCollector", category: "SpeciesCatalog")

    init(bundle: Bundle = .main) {
        pictureStyle = PictureStyle(rawValue: UserDefaults.standard.string(forKey: Self.pictureStyleKey) ?? "") ?? .watercolour
        let definitions = Self.loadGroupDefinitions(bundle: bundle)
        if definitions.isEmpty { record("Bird groups unavailable") }

        for region in Region.allCases {
            guard let url = bundle.url(forResource: "taxonomy_\(region.rawValue)", withExtension: "json") else {
                continue
            }
            do {
                let result = try Self.decode(Data(contentsOf: url))
                let regionSpecies = result.species
                groupsByRegion[region] = SpeciesGrouping.build(definitions: definitions, species: regionSpecies)
                byRegion[region] = regionSpecies
                for species in regionSpecies where byCode[species.ebirdCode] == nil {
                    byCode[species.ebirdCode] = species
                }
                if result.skipped > 0 {
                    record("\(region.rawValue): skipped \(result.skipped) unreadable species")
                }
            } catch {
                record("\(region.rawValue): couldn't read species list — \(error.localizedDescription)")
            }
            loadArtwork(region: region, bundle: bundle)
        }
    }

    /// Paintings live in the `Art` folder: `art_<REGION>.json` plus `<REGION>/<code>.jpg`.
    /// Builds without them just show photos.
    private func loadArtwork(region: Region, bundle: Bundle) {
        guard let url = bundle.url(forResource: "art_\(region.rawValue)", withExtension: "json", subdirectory: "Art"),
              let data = try? Data(contentsOf: url) else { return }
        do {
            let manifest = try JSONDecoder().decode(ArtManifest.self, from: data)
            let folder = url.deletingLastPathComponent().appendingPathComponent(region.rawValue, isDirectory: true)
            for (code, art) in manifest.species {
                let file = folder.appendingPathComponent(art.file)
                if FileManager.default.fileExists(atPath: file.path) { artwork[code] = (art, file) }
            }
        } catch {
            record("\(region.rawValue): couldn't read watercolours — \(error.localizedDescription)")
        }
    }

    var hasArtwork: Bool { !artwork.isEmpty }

    func artwork(for species: Species) -> (art: Artwork, url: URL)? {
        artwork[species.ebirdCode]
    }

    /// The field guide picture for a species: its watercolour when chosen and
    /// available, otherwise the photo.
    func picture(for species: Species?) -> URL? {
        guard let species else { return nil }
        if pictureStyle == .watercolour, let art = artwork[species.ebirdCode] { return art.url }
        return species.thumbnail
    }

    /// Regions that actually have species data in this build.
    var availableRegions: [Region] {
        Region.allCases.filter { !(byRegion[$0]?.isEmpty ?? true) }
    }

    func species(in region: Region) -> [Species] {
        byRegion[region] ?? []
    }

    func species(code: String) -> Species? {
        byCode[code]
    }

    /// Curated bird groups followed by genera, for a region.
    func groups(in region: Region) -> [SpeciesGroup] {
        groupsByRegion[region]?.groups ?? []
    }

    func groups(containing code: String, in region: Region) -> [SpeciesGroup] {
        groupsByRegion[region]?.byCode[code] ?? []
    }

    private static func loadGroupDefinitions(bundle: Bundle) -> [GroupDefinition] {
        guard
            let url = bundle.url(forResource: "groups", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let definitions = try? JSONDecoder().decode([GroupDefinition].self, from: data)
        else { return [] }
        return definitions
    }

    /// Decodes a taxonomy file, skipping (and counting) records that can't be
    /// read rather than failing the whole list.
    nonisolated static func decode(_ data: Data) throws -> (species: [Species], skipped: Int) {
        let items = try JSONDecoder().decode([Failable<Species>].self, from: data)
        let species = items.compactMap(\.value)
        return (species, items.count - species.count)
    }

    private func record(_ issue: String) {
        loadIssues.append(issue)
        Self.log.error("\(issue, privacy: .public)")
    }
}

/// Decodes `T` if it can, otherwise stores nil instead of throwing.
private struct Failable<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

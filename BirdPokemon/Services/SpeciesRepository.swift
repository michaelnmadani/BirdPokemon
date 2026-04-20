import Foundation
import FirebaseFirestore

actor SpeciesRepository {
    static let shared = SpeciesRepository()

    private var collection: CollectionReference {
        FirebaseService.firestore.collection(FirebaseService.Collection.speciesCache)
    }

    private var memoryCache: [String: Species] = [:]
    private var byRegion: [String: [Species]] = [:]
    private var bundledLoaded: Bool = false

    /// Loads species shipped in the app bundle (per-region JSON). Cheap and
    /// offline-safe. Firestore reads layer on top of this for freshness.
    private func loadBundledIfNeeded() {
        guard !bundledLoaded else { return }
        bundledLoaded = true
        for region in Region.allCases {
            guard let url = Bundle.main.url(forResource: "taxonomy_\(region.rawValue)",
                                            withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let decoded = try? JSONDecoder.speciesDecoder.decode([Species].self, from: data)
            else { continue }
            byRegion[region.rawValue] = decoded
            for s in decoded { memoryCache[s.ebirdCode] = s }
        }
    }

    func species(for code: String) async -> Species? {
        loadBundledIfNeeded()
        if let cached = memoryCache[code] { return cached }
        do {
            let snap = try await collection.document(code).getDocument()
            let species = try snap.data(as: Species.self)
            memoryCache[code] = species
            return species
        } catch {
            print("SpeciesRepository: fetch \(code) failed — \(error)")
            return nil
        }
    }

    func speciesList(region: Region) async -> [Species] {
        loadBundledIfNeeded()
        if let bundled = byRegion[region.rawValue], !bundled.isEmpty {
            return bundled
        }
        do {
            let snap = try await collection
                .whereField("regionCodes", arrayContains: region.rawValue)
                .order(by: "commonName")
                .getDocuments()
            let list = snap.documents.compactMap { try? $0.data(as: Species.self) }
            byRegion[region.rawValue] = list
            for s in list { memoryCache[s.ebirdCode] = s }
            return list
        } catch {
            print("SpeciesRepository: region fetch failed — \(error)")
            return []
        }
    }

    func allKnownSpecies() -> [Species] {
        loadBundledIfNeeded()
        return Array(memoryCache.values).sorted { $0.commonName < $1.commonName }
    }
}

extension JSONDecoder {
    static let speciesDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

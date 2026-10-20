import Foundation
import os

/// Keeps sightings on the device: an index in `sightings.json` plus two JPEGs
/// per sighting under `Photos/`. Lives in Application Support, which is
/// included in iCloud/iTunes device backups.
@MainActor
final class LocalSightingBackend: SightingBackend {
    static let localUserId = "local"

    let directory: URL
    private var photosDirectory: URL { directory.appendingPathComponent("Photos", isDirectory: true) }
    private var indexURL: URL { directory.appendingPathComponent("sightings.json") }

    private var sightings: [Sighting] = []
    private var onUpdate: (@MainActor (Result<[Sighting], Error>) -> Void)?
    private let fileManager = FileManager.default
    private static let log = Logger(subsystem: "DownUnderBirdCollector", category: "LocalSightingBackend")

    init(directory: URL) {
        self.directory = directory
    }

    static func defaultDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return base.appendingPathComponent("Sightings", isDirectory: true)
    }

    func start(onUpdate: @escaping @MainActor (Result<[Sighting], Error>) -> Void) {
        self.onUpdate = onUpdate
        do {
            try fileManager.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
            sightings = try loadIndex()
            onUpdate(.success(sightings))
        } catch {
            onUpdate(.failure(error))
        }
    }

    func stop() {
        onUpdate = nil
    }

    func add(_ draft: SightingDraft, photo: ProcessedPhoto) async throws -> Sighting {
        let id = UUID().uuidString
        let photoFile = "\(id).jpg"
        let thumbnailFile = "\(id)_thumb.jpg"
        try fileManager.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        try photo.full.write(to: photosDirectory.appendingPathComponent(photoFile), options: .atomic)
        try photo.thumbnail.write(to: photosDirectory.appendingPathComponent(thumbnailFile), options: .atomic)

        let sighting = Sighting(
            id: id,
            userId: Self.localUserId,
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
            localPhotoFile: photoFile,
            localThumbnailFile: thumbnailFile
        )

        do {
            try saveIndex(sightings + [sighting])
        } catch {
            removeFiles(of: sighting)
            throw error
        }
        sightings.append(sighting)
        publish()
        return sighting
    }

    func delete(_ sighting: Sighting) async throws {
        let remaining = sightings.filter { $0.id != sighting.id }
        try saveIndex(remaining)
        sightings = remaining
        removeFiles(of: sighting)
        publish()
    }

    func photoURL(for sighting: Sighting) -> URL? {
        sighting.localPhotoFile.map { photosDirectory.appendingPathComponent($0) }
    }

    func thumbnailURL(for sighting: Sighting) -> URL? {
        (sighting.localThumbnailFile ?? sighting.localPhotoFile).map { photosDirectory.appendingPathComponent($0) }
    }

    // MARK: - Persistence

    private func loadIndex() throws -> [Sighting] {
        guard fileManager.fileExists(atPath: indexURL.path) else { return [] }
        let data = try Data(contentsOf: indexURL)
        do {
            return try Self.decoder.decode([Sighting].self, from: data)
        } catch {
            // Never overwrite a file we couldn't read: set it aside and start fresh.
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = directory.appendingPathComponent("sightings.unreadable-\(stamp).json")
            try? fileManager.moveItem(at: indexURL, to: backup)
            Self.log.error("Unreadable sightings index moved to \(backup.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw LocalStoreError.unreadableIndex(backupName: backup.lastPathComponent)
        }
    }

    private func saveIndex(_ list: [Sighting]) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.encoder.encode(list).write(to: indexURL, options: .atomic)
    }

    private func removeFiles(of sighting: Sighting) {
        for name in [sighting.localPhotoFile, sighting.localThumbnailFile].compactMap({ $0 }) {
            try? fileManager.removeItem(at: photosDirectory.appendingPathComponent(name))
        }
    }

    private func publish() {
        onUpdate?(.success(sightings))
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    enum LocalStoreError: LocalizedError {
        case unreadableIndex(backupName: String)

        var errorDescription: String? {
            switch self {
            case .unreadableIndex(let name):
                return "Your saved sightings couldn't be read. The old file was kept as \(name)."
            }
        }
    }
}

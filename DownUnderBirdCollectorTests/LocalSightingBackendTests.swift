import XCTest
import CoreLocation
@testable import DownUnderBirdCollector

@MainActor
final class LocalSightingBackendTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalSightingBackendTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func draft(code: String = "laukoo1", coordinate: CLLocationCoordinate2D? = nil) -> SightingDraft {
        SightingDraft(
            species: TestFixtures.species(code: code, name: "Laughing Kookaburra"),
            photo: CapturedPhoto(image: TestFixtures.image(width: 3000, height: 2000), source: .camera),
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            coordinate: coordinate,
            locationSource: coordinate == nil ? nil : .device
        )
    }

    func testAddPersistsPhotosAndIndexAcrossReload() async throws {
        let store = SightingStore(backend: LocalSightingBackend(directory: directory))
        let coordinate = CLLocationCoordinate2D(latitude: -33.87, longitude: 151.21)
        let saved = try await store.add(draft(coordinate: coordinate))

        XCTAssertEqual(store.sightings.map(\.id), [saved.id])
        XCTAssertTrue(store.capturedCodes.contains("laukoo1"))
        XCTAssertEqual(saved.latitude, -33.87)
        XCTAssertEqual(saved.locationSource, .device)

        let photo = try XCTUnwrap(store.photoURL(for: saved))
        let thumbnail = try XCTUnwrap(store.thumbnailURL(for: saved))
        let fullImage = try XCTUnwrap(UIImage(contentsOfFile: photo.path))
        let thumbImage = try XCTUnwrap(UIImage(contentsOfFile: thumbnail.path))
        XCTAssertEqual(max(fullImage.size.width, fullImage.size.height), ImageProcessing.fullMaxDimension)
        XCTAssertEqual(max(thumbImage.size.width, thumbImage.size.height), ImageProcessing.thumbnailMaxDimension)

        // A fresh backend over the same folder sees the same data.
        let reloaded = SightingStore(backend: LocalSightingBackend(directory: directory))
        XCTAssertEqual(reloaded.sightings.map(\.id), [saved.id])
        XCTAssertEqual(reloaded.sightings.first?.capturedAt, saved.capturedAt)
    }

    func testSightingWithoutLocationHasNoCoordinate() async throws {
        let store = SightingStore(backend: LocalSightingBackend(directory: directory))
        let saved = try await store.add(draft())
        XCTAssertNil(saved.coordinate)
        XCTAssertNil(saved.latitude)
    }

    func testDeleteRemovesFilesAndUncollectsSpecies() async throws {
        let store = SightingStore(backend: LocalSightingBackend(directory: directory))
        let first = try await store.add(draft(code: "laukoo1"))
        let second = try await store.add(draft(code: "galah"))
        let photo = try XCTUnwrap(store.photoURL(for: first))

        await store.delete(ids: [first.id])

        XCTAssertEqual(store.sightings.map(\.id), [second.id])
        XCTAssertFalse(store.capturedCodes.contains("laukoo1"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: photo.path))
    }

    func testLatestSightingPerSpecies() async throws {
        let store = SightingStore(backend: LocalSightingBackend(directory: directory))
        var older = draft()
        older.capturedAt = Date(timeIntervalSince1970: 1_000)
        _ = try await store.add(older)
        let newer = try await store.add(draft())
        XCTAssertEqual(store.latestSighting(of: "laukoo1")?.id, newer.id)
        XCTAssertEqual(store.sightings(of: "laukoo1").count, 2)
    }

    func testUnreadableIndexIsSetAsideNotOverwritten() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: directory.appendingPathComponent("sightings.json"))

        let store = SightingStore(backend: LocalSightingBackend(directory: directory))
        XCTAssertNotNil(store.lastError)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertTrue(files.contains { $0.hasPrefix("sightings.unreadable-") })
    }

    func testUserOverrodeComparesToModelPick() {
        var value = draft(code: "laukoo1")
        XCTAssertFalse(value.userOverrode)
        value.mlTopPrediction = Prediction(speciesCode: "bluwin1", commonName: "Blue-winged Kookaburra", confidence: 0.6)
        XCTAssertTrue(value.userOverrode)
    }
}

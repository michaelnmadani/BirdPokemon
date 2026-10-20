import XCTest
@testable import DownUnderBirdCollector

@MainActor
final class SoundIDCoreTests: XCTestCase {
    private lazy var catalog = SpeciesCatalog(bundle: Bundle(for: SpeciesCatalog.self))

    func testParseLabelsFlagsNonBirds() {
        XCTAssertEqual(SoundIDCore.parseLabels("Dacelo novaeguineae_Laughing Kookaburra\nEngine_Engine\n"), [
            SoundLabel(scientificName: "Dacelo novaeguineae", commonName: "Laughing Kookaburra", isBird: true),
            SoundLabel(scientificName: "Engine", commonName: "Engine", isBird: false),
        ])
    }

    func testLabelsMapBySciThenCommonName() {
        let labels = SoundIDCore.parseLabels("""
        Dacelo novaeguineae_Laughing Kookaburra
        Calyptorhynchus funereus_Yellow-tailed Black-Cockatoo
        Poecile atricapillus_Black-capped Chickadee
        Engine_Engine
        """)
        XCTAssertEqual(SoundIDCore.mapLabels(labels, to: catalog.species(in: .australia)), ["laukoo1", "ytblco1", nil, nil])
    }

    func testSigmoidAndDetections() {
        XCTAssertEqual(SoundIDCore.sigmoid(0), 0.5)
        XCTAssertLessThanOrEqual(SoundIDCore.sigmoid(100), 1)
        XCTAssertGreaterThanOrEqual(SoundIDCore.sigmoid(-100), 0)
        let found = SoundIDCore.detections([2, -3, 0.1, 5]) { $0 != 3 }
        XCTAssertEqual(found.map(\.index), [0, 2])
    }

    func testAudioHelpers() {
        XCTAssertEqual(SoundIDCore.mixToMono([[1, 0], [0, 1]]), [0.5, 0.5])
        let up = SoundIDCore.resample([Float](repeating: 0.25, count: 44_100), from: 44_100)
        XCTAssertEqual(up.count, 48_000)
        XCTAssertEqual(up[1000], 0.25, accuracy: 1e-6)
        let w = SoundIDCore.windows([Float](repeating: 0, count: SoundIDCore.window * 2 + 72_000))
        XCTAssertEqual(w.count, 3, "two full windows plus a padded 1.5 s tail")
        XCTAssertEqual(w.last?.samples.count, SoundIDCore.window)
        XCTAssertEqual(SoundIDCore.windows([Float](repeating: 0, count: SoundIDCore.window + 100)).count, 1,
                       "tails under a second are dropped")
    }

    func testTallyKeepsBestAndCounts() {
        var tally: [Int: SoundTallyEntry] = [:]
        SoundIDCore.addToTally(&tally, [SoundDetection(index: 4, confidence: 0.4)], at: 0)
        SoundIDCore.addToTally(&tally, [SoundDetection(index: 4, confidence: 0.9), SoundDetection(index: 7, confidence: 0.3)], at: 3)
        XCTAssertEqual(SoundIDCore.rank(tally).map { [$0.index, $0.count] }, [[4, 2], [7, 1]])
        XCTAssertEqual(tally[4]?.best, 0.9)
        XCTAssertEqual(tally[4]?.lastAt, 3)
    }
}

/// Runs the real BirdNET model with TensorFlow Lite on BirdNET's example
/// recording. Reference scores come from the Python LiteRT interpreter.
@MainActor
final class BirdNETModelTests: XCTestCase {
    func testIdentifiesTheExampleSoundscape() async throws {
        try XCTSkipUnless(SoundIdentifier.isAvailable, "BirdNET model not bundled (run scripts/birdnet/fetch-model.sh)")
        let recording = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "soundscape", withExtension: "wav"),
                                      "run scripts/birdnet/fetch-model.sh --example")
        let catalog = SpeciesCatalog(bundle: Bundle(for: SpeciesCatalog.self))
        let identifier = try SoundIdentifier(species: catalog.species(in: .australia))
        XCTAssertEqual(identifier.labels.count, 6522)
        XCTAssertGreaterThanOrEqual(Set(identifier.codes.compactMap { $0 }).count, 360)

        let samples = try SoundIdentifier.decode(url: recording)
        XCTAssertEqual(samples.count, 120 * 48_000)
        let windows = SoundIDCore.windows(samples)
        let chickadee = try XCTUnwrap(identifier.labels.firstIndex { $0.commonName == "Black-capped Chickadee" })
        let finch = try XCTUnwrap(identifier.labels.firstIndex { $0.commonName == "House Finch" })

        let first = try await identifier.classify(windows[0].samples)
        XCTAssertEqual(first.count, 6522)
        XCTAssertEqual(SoundIDCore.sigmoid(first[chickadee]), 0.814, accuracy: 0.02)
        XCTAssertEqual(SoundIDCore.detections(first).first?.index, chickadee)

        let fourth = try await identifier.classify(windows[3].samples)
        XCTAssertEqual(SoundIDCore.detections(fourth).first?.index, finch)
        XCTAssertEqual(SoundIDCore.sigmoid(fourth[finch]), 0.639, accuracy: 0.02)
    }
}

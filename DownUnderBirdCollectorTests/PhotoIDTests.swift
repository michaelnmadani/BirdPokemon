import XCTest
@testable import DownUnderBirdCollector

@MainActor
final class PhotoIDTests: XCTestCase {
    private lazy var catalog = SpeciesCatalog(bundle: Bundle(for: SpeciesCatalog.self))

    private func labels() throws -> [PhotoLabel] {
        let url = try XCTUnwrap(Bundle(for: SpeciesCatalog.self).url(forResource: "BirdPhotoClassifier_labels", withExtension: "txt"))
        return PhotoIDCore.parseLabels(try String(contentsOf: url, encoding: .utf8))
    }

    func testLabelsParse() throws {
        XCTAssertEqual(try labels().count, 965)
        XCTAssertEqual(PhotoIDCore.parseLabels("Dacelo novaeguineae (Laughing Kookaburra)\nbackground\n"), [
            PhotoLabel(scientificName: "Dacelo novaeguineae", commonName: "Laughing Kookaburra"),
            PhotoLabel(scientificName: "background", commonName: ""),
        ])
    }

    func testSeventySevenFieldGuideSpeciesAreRecognisable() throws {
        let labels = try labels()
        let codes = PhotoIDCore.mapLabels(labels, to: catalog.species(in: .australia))
        XCTAssertEqual(Set(codes.compactMap { $0 }).count, 77)
        func code(_ sci: String) -> String? { labels.firstIndex { $0.scientificName == sci }.flatMap { codes[$0] } }
        XCTAssertEqual(code("Dacelo novaeguineae"), "laukoo1")
        XCTAssertEqual(code("Threskiornis moluccus"), "auwhib1", "Australian Ibis = Australian White Ibis")
        XCTAssertEqual(PhotoIDCore.latinStem("Threskiornis moluccus"), PhotoIDCore.latinStem("Threskiornis molucca"))
        XCTAssertNil(code("Turdus migratorius"))
    }

    func testSuggestionsAreFieldGuideBirdsOnlyAndFlagUncertainty() {
        let codes: [String?] = [nil, "laukoo1", "galah", nil, "laukoo1"]
        let sure = PhotoIDCore.suggestions([0.01, 0.8, 0.06, 0.1, 0.03], codes: codes)
        XCTAssertEqual(sure.suggestions.map(\.code), ["laukoo1", "galah"])
        XCTAssertFalse(sure.unsure)
        let foreign = PhotoIDCore.suggestions([0.9, 0.04, 0.06, 0, 0], codes: codes)
        XCTAssertEqual(foreign.suggestions.map(\.code), ["galah"])
        XCTAssertTrue(foreign.unsure)
        XCTAssertEqual(PhotoIDCore.dequantize([0, 128]), [0, 0.5])
    }

    /// The real model on a kookaburra photo (the Python LiteRT reference gives 0.84).
    func testIdentifiesAKookaburraPhoto() async throws {
        try XCTSkipUnless(PhotoIdentifier.isAvailable, "photo model not bundled")
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "kookaburra", withExtension: "jpg"))
        let image = try XCTUnwrap(UIImage(contentsOfFile: url.path))
        let identifier = try PhotoIdentifier(species: catalog.species(in: .australia))
        let result = try await identifier.identify(image)
        XCTAssertEqual(result.suggestions.first?.code, "laukoo1")
        XCTAssertGreaterThan(result.suggestions.first?.confidence ?? 0, 0.5)
        XCTAssertFalse(result.unsure)
        XCTAssertEqual(PhotoIdentifier.pixels(of: image)?.count, 224 * 224 * 3)
    }
}

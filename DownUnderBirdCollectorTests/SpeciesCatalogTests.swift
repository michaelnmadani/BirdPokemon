import XCTest
@testable import DownUnderBirdCollector

@MainActor
final class SpeciesCatalogTests: XCTestCase {
    /// The bundled Australian list must load completely — this is the
    /// regression test for the catalog silently coming up empty.
    func testBundledAustralianTaxonomyLoadsCompletely() throws {
        let catalog = SpeciesCatalog(bundle: Bundle(for: SpeciesCatalog.self))
        XCTAssertEqual(catalog.loadIssues, [])
        XCTAssertGreaterThanOrEqual(catalog.species(in: .australia).count, 500)
        XCTAssertEqual(catalog.species(code: "emu1")?.commonName, "Emu")
        XCTAssertTrue(catalog.availableRegions.contains(.australia))
    }

    func testBundledTaxonomyUsesOnlyKnownColoursAndSizes() throws {
        let url = try XCTUnwrap(Bundle(for: SpeciesCatalog.self).url(forResource: "taxonomy_AU", withExtension: "json"))
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        for record in raw {
            let code = record["ebirdCode"] as? String ?? "?"
            for color in record["primaryColors"] as? [String] ?? [] {
                XCTAssertNotNil(BirdColor(rawValue: color), "\(code) has unknown colour \(color)")
            }
            let size = record["sizeCategory"] as? String ?? ""
            XCTAssertNotNil(SizeCategory(rawValue: size), "\(code) has unknown size \(size)")
        }
    }

    func testDecodingIsLenientAboutColoursAndSize() throws {
        let json = """
        [{"ebirdCode":"rufwhi1","commonName":"Rufous Whistler","scientificName":"Pachycephala rufiventris",
          "sizeCategory":"enormous","primaryColors":["rufous","grey","grey","streaked","white"],
          "regionCodes":["AU"]}]
        """
        let result = try SpeciesCatalog.decode(Data(json.utf8))
        let species = try XCTUnwrap(result.species.first)
        XCTAssertEqual(result.skipped, 0)
        XCTAssertEqual(species.primaryColors, [.orange, .gray, .white])
        XCTAssertEqual(species.sizeCategory, .medium)
        XCTAssertEqual(species.family, "Unknown")
        XCTAssertEqual(species.ebirdURL, "https://ebird.org/species/rufwhi1")
    }

    func testBrokenRecordIsSkippedNotFatal() throws {
        let json = """
        [{"ebirdCode":"good1","commonName":"Good","scientificName":"Bonus bonus"},
         {"commonName":"No code"}]
        """
        let result = try SpeciesCatalog.decode(Data(json.utf8))
        XCTAssertEqual(result.species.map(\.ebirdCode), ["good1"])
        XCTAssertEqual(result.skipped, 1)
    }

    func testPhotoCreditFormatsLicence() {
        XCTAssertEqual(Species.licenceLabel("cc-by-nc"), "CC BY-NC")
        XCTAssertEqual(Species.licenceLabel("cc0"), "CC0")
    }
}

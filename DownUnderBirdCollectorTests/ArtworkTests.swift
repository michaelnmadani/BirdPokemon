import XCTest
@testable import DownUnderBirdCollector

@MainActor
final class ArtworkTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        // A throwaway bundle: the real species list plus two paintings, one of
        // them missing its image file.
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let art = folder.appendingPathComponent("Art/AU", isDirectory: true)
        try FileManager.default.createDirectory(at: art, withIntermediateDirectories: true)
        let taxonomy = try XCTUnwrap(Bundle(for: SpeciesCatalog.self).url(forResource: "taxonomy_AU", withExtension: "json"))
        try FileManager.default.copyItem(at: taxonomy, to: folder.appendingPathComponent("taxonomy_AU.json"))
        try Data([0xFF, 0xD8, 0xFF]).write(to: art.appendingPathComponent("laukoo1.jpg"))
        try Data("""
        {"version": 1, "species": {
          "laukoo1": {"file": "laukoo1.jpg", "photoAttribution": "© Jane Doe", "photoLicense": "cc-by-sa", "license": "cc-by-sa"},
          "emu1": {"file": "emu1.jpg", "photoAttribution": "© Someone", "photoLicense": "cc-by-nc"},
          "galah1": {"nope": true}
        }}
        """.utf8).write(to: folder.appendingPathComponent("Art/art_AU.json"))
        UserDefaults.standard.removeObject(forKey: SpeciesCatalog.pictureStyleKey)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
        UserDefaults.standard.removeObject(forKey: SpeciesCatalog.pictureStyleKey)
    }

    func testCreditNamesThePhotoItWasPaintedFrom() {
        let art = Artwork(file: "x.jpg", photoAttribution: "© Jane Doe", photoLicense: "cc-by-nc", license: "cc-by-nc")
        XCTAssertEqual(art.credit, "Watercolour after a photo by © Jane Doe · CC BY-NC via iNaturalist")
        XCTAssertEqual(Artwork(file: "x.jpg").credit, "Watercolour after a photo via iNaturalist")
    }

    func testCatalogUsesPaintingsThatExistAndFollowsTheSetting() throws {
        let catalog = SpeciesCatalog(bundle: try XCTUnwrap(Bundle(path: folder.path)))
        let kookaburra = try XCTUnwrap(catalog.species(code: "laukoo1"))
        let emu = try XCTUnwrap(catalog.species(code: "emu1"))

        XCTAssertEqual(catalog.artwork.count, 1, "missing files and unreadable entries are skipped")
        XCTAssertEqual(catalog.pictureStyle, .watercolour)
        XCTAssertEqual(catalog.picture(for: kookaburra)?.lastPathComponent, "laukoo1.jpg")
        XCTAssertEqual(catalog.picture(for: emu), emu.thumbnail, "no painting, so the photo")

        catalog.pictureStyle = .photo
        XCTAssertEqual(catalog.picture(for: kookaburra), kookaburra.thumbnail)
        XCTAssertEqual(UserDefaults.standard.string(forKey: SpeciesCatalog.pictureStyleKey), "photo")
        XCTAssertEqual(SpeciesCatalog(bundle: try XCTUnwrap(Bundle(path: folder.path))).pictureStyle, .photo, "remembered")
    }

    func testSpeciesWithoutPaintingsShowPhotos() throws {
        let catalog = SpeciesCatalog(bundle: Bundle(for: SpeciesCatalog.self))
        for species in catalog.species(in: .australia) where catalog.artwork(for: species) == nil {
            XCTAssertEqual(catalog.picture(for: species), species.thumbnail, species.ebirdCode)
        }
        XCTAssertNil(catalog.picture(for: nil))
    }

    func testCreditsLinkToTheLicence() {
        XCTAssertEqual(CreditsView.licenceURL("cc-by-nc")?.absoluteString, "https://creativecommons.org/licenses/by-nc/4.0/")
        XCTAssertEqual(CreditsView.licenceURL("cc0")?.absoluteString, "https://creativecommons.org/publicdomain/zero/1.0/")
        XCTAssertNil(CreditsView.licenceURL("all-rights"))
    }
}

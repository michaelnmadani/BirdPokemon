import XCTest
@testable import BirdPokemon

final class FilterCriteriaTests: XCTestCase {
    private func species(code: String = "testspc",
                         family: String = "Testidae",
                         size: SizeCategory = .medium,
                         colors: [BirdColor] = [.brown],
                         regions: [String] = ["AU"],
                         name: String = "Test Bird") -> Species {
        Species(
            ebirdCode: code,
            commonName: name,
            scientificName: "Testus testus",
            order: "Testiformes",
            family: family,
            familyCommonName: nil,
            category: "species",
            sizeCategory: size,
            primaryColors: colors,
            regionCodes: regions,
            thumbnailURL: nil,
            wikipediaURL: nil,
            ebirdURL: "https://example.com",
            updatedAt: nil
        )
    }

    func testEmptyCriteriaMatchesEverything() {
        let criteria = FilterCriteria()
        XCTAssertTrue(criteria.matches(species()))
    }

    func testRegionFilter() {
        var criteria = FilterCriteria()
        criteria.regions = [.newZealand]
        XCTAssertFalse(criteria.matches(species(regions: ["AU"])))
        XCTAssertTrue(criteria.matches(species(regions: ["NZ", "AU"])))
    }

    func testSizeFilter() {
        var criteria = FilterCriteria()
        criteria.sizes = [.tiny, .small]
        XCTAssertFalse(criteria.matches(species(size: .medium)))
        XCTAssertTrue(criteria.matches(species(size: .small)))
    }

    func testColorFilterIntersects() {
        var criteria = FilterCriteria()
        criteria.colors = [.red, .blue]
        XCTAssertTrue(criteria.matches(species(colors: [.blue, .green])))
        XCTAssertFalse(criteria.matches(species(colors: [.brown])))
    }

    func testSearchMatchesCommonName() {
        var criteria = FilterCriteria()
        criteria.searchText = "Kookaburra"
        XCTAssertTrue(criteria.matches(species(name: "Laughing Kookaburra")))
        XCTAssertFalse(criteria.matches(species(name: "Emu")))
    }

    func testActiveFilterCount() {
        var criteria = FilterCriteria()
        criteria.regions = [.australia]
        criteria.sizes = [.small]
        XCTAssertEqual(criteria.activeFilterCount, 2)
    }
}

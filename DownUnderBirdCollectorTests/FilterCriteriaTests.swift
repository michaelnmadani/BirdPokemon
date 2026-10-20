import XCTest
@testable import DownUnderBirdCollector

final class FilterCriteriaTests: XCTestCase {
    private func species(code: String = "testspc",
                         family: String = "Testidae",
                         familyCommonName: String? = nil,
                         size: SizeCategory = .medium,
                         colors: [BirdColor] = [.brown],
                         name: String = "Test Bird") -> Species {
        TestFixtures.species(code: code, family: family, familyCommonName: familyCommonName,
                             size: size, colors: colors, name: name)
    }

    func testEmptyCriteriaMatchesEverything() {
        let criteria = FilterCriteria()
        XCTAssertTrue(criteria.isEmpty)
        XCTAssertTrue(criteria.matches(species()))
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

    func testFamilyFilter() {
        var criteria = FilterCriteria()
        criteria.families = ["Alcedinidae"]
        XCTAssertTrue(criteria.matches(species(family: "Alcedinidae")))
        XCTAssertFalse(criteria.matches(species(family: "Meliphagidae")))
    }

    func testSearchMatchesCommonNameCaseInsensitively() {
        var criteria = FilterCriteria()
        criteria.searchText = "kookaburra "
        XCTAssertTrue(criteria.matches(species(name: "Laughing Kookaburra")))
        XCTAssertFalse(criteria.matches(species(name: "Emu")))
    }

    func testSearchMatchesFamilyCommonName() {
        var criteria = FilterCriteria()
        criteria.searchText = "honeyeater"
        XCTAssertTrue(criteria.matches(species(familyCommonName: "Honeyeaters", name: "Noisy Miner")))
    }

    func testActiveFilterCountIgnoresSearch() {
        var criteria = FilterCriteria()
        criteria.sizes = [.small]
        criteria.colors = [.red]
        criteria.searchText = "robin"
        XCTAssertEqual(criteria.activeFilterCount, 2)
    }
}

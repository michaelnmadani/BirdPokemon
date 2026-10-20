import XCTest
@testable import DownUnderBirdCollector

@MainActor
final class SpeciesGroupingTests: XCTestCase {
    private lazy var catalog = SpeciesCatalog(bundle: Bundle(for: SpeciesCatalog.self))

    private func group(_ id: String) throws -> SpeciesGroup {
        try XCTUnwrap(catalog.groups(in: .australia).first { $0.id == id }, "missing group \(id)")
    }

    func testPlural() {
        XCTAssertEqual(SpeciesGrouping.plural("Rosella"), "Rosellas")
        XCTAssertEqual(SpeciesGrouping.plural("Finch"), "Finches")
        XCTAssertEqual(SpeciesGrouping.plural("Ibis"), "Ibises")
        XCTAssertEqual(SpeciesGrouping.plural("Goose"), "Geese")
        XCTAssertEqual(SpeciesGrouping.plural("Black-Cockatoo"), "Black-Cockatoos")
    }

    func testGenusLabel() {
        XCTAssertEqual(SpeciesGrouping.genusLabel(["Crimson Rosella", "Eastern Rosella", "Green Rosella"]), "Rosellas")
        XCTAssertEqual(SpeciesGrouping.genusLabel(["Great Egret", "Pacific Heron", "Little Egret", "Great-billed Heron"]),
                       "Egrets & Herons")
        XCTAssertEqual(SpeciesGrouping.genusLabel(["Carpentarian Grasswren (alt)", "Dusky Grasswren"]), "Grasswrens")
    }

    func testCuratedGroupsFromBundle() throws {
        XCTAssertEqual(Set(try group("flightless").species.map(\.commonName)),
                       ["Emu", "Southern Cassowary", "Little Penguin"])
        let parrots = Set(try group("parrots").species.map(\.commonName))
        XCTAssertTrue(parrots.isSuperset(of: ["Galah", "Rainbow Lorikeet", "Sulphur-crested Cockatoo"]))
        XCTAssertEqual(try group("introduced").species.count, 6)
        XCTAssertFalse(try group("shorebirds").species.contains { $0.commonName == "Silver Gull" })
    }

    func testEverySpeciesHasABirdGroup() {
        for species in catalog.species(in: .australia) {
            let groups = catalog.groups(containing: species.ebirdCode, in: .australia)
            XCTAssertTrue(groups.contains { $0.kind == .group }, species.commonName)
        }
    }

    func testGeneraBecomeGroups() throws {
        let rosellas = try XCTUnwrap(catalog.groups(in: .australia).first { $0.genus == "Platycercus" })
        XCTAssertEqual(rosellas.name, "Rosellas")
        XCTAssertGreaterThanOrEqual(rosellas.species.count, 5)
        XCTAssertFalse(catalog.groups(in: .australia).contains { $0.genus == "Dromaius" })
    }

    func testGroupNamesAreSearchable() throws {
        var criteria = FilterCriteria()
        criteria.searchText = "parrot"
        let galah = try XCTUnwrap(catalog.species(in: .australia).first { $0.commonName == "Galah" })
        XCTAssertTrue(criteria.matches(galah))
        XCTAssertTrue(SpeciesGrouping.matching(catalog.groups(in: .australia), query: "rosel")
            .contains { $0.genus == "Platycercus" })
        XCTAssertTrue(SpeciesGrouping.matching(catalog.groups(in: .australia), query: "ro").isEmpty)
    }
}

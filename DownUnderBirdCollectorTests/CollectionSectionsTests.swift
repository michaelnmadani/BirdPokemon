import XCTest
@testable import DownUnderBirdCollector

@MainActor
final class CollectionSectionsTests: XCTestCase {
    private lazy var catalog = SpeciesCatalog(bundle: Bundle(for: SpeciesCatalog.self))
    private var species: [Species] { catalog.species(in: .australia) }

    private func section(of name: String, in sections: [CollectionSection]) -> CollectionSection? {
        sections.first { $0.species.contains { $0.commonName == name } }
    }

    func testNoGroupingIsOneUntitledSection() {
        let sections = CollectionSections.build(species, by: .none)
        XCTAssertEqual(sections.count, 1)
        XCTAssertNil(sections[0].title)
        XCTAssertEqual(sections[0].species.count, species.count)
    }

    func testEveryGroupingListsEachSpeciesOnce() {
        for grouping in CollectionGrouping.allCases where grouping != .none {
            let sections = CollectionSections.build(species, by: grouping, groups: catalog.groups(in: .australia))
            let codes = sections.flatMap { $0.species.map(\.ebirdCode) }
            XCTAssertEqual(codes.count, species.count, "\(grouping)")
            XCTAssertEqual(Set(codes).count, species.count, "\(grouping)")
            XCTAssertTrue(sections.allSatisfy { !$0.species.isEmpty && $0.title != nil }, "\(grouping)")
        }
    }

    func testBirdGroupsFollowCuratedOrder() {
        let sections = CollectionSections.build(species, by: .group, groups: catalog.groups(in: .australia))
        XCTAssertEqual(sections.first?.title, "Flightless birds")
        XCTAssertEqual(section(of: "Emu", in: sections)?.id, "flightless")
        XCTAssertEqual(section(of: "Galah", in: sections)?.id, "parrots")
        XCTAssertEqual(section(of: "Rock Dove", in: sections)?.id, "pigeons", "introduced pigeons stay with pigeons")
    }

    func testSizesAndColours() {
        let bySize = CollectionSections.build(species, by: .size)
        XCTAssertEqual(bySize.map(\.id), SizeCategory.allCases.map(\.rawValue).filter { id in bySize.contains { $0.id == id } })
        XCTAssertEqual(section(of: "Emu", in: bySize)?.id, "huge")
        let byColour = CollectionSections.build(species, by: .colour)
        XCTAssertTrue(byColour.allSatisfy { $0.id == "unknown" || $0.swatch != nil })
        XCTAssertTrue(byColour.contains { $0.title == "Grey" })
    }

    func testFamiliesKeepTaxonomicOrder() {
        let some = species.filter { ["Emu", "Galah", "Sulphur-crested Cockatoo"].contains($0.commonName) }
        let sections = CollectionSections.build(some, by: .family)
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].species.first?.commonName, "Emu")
        XCTAssertEqual(sections[1].species.count, 2)
    }

    func testGridSizesGrow() {
        let widths = CollectionGridSize.allCases.map(\.minimumWidth)
        XCTAssertEqual(widths, widths.sorted())
        XCTAssertEqual(CollectionGridSize.allCases.map(\.label), ["S", "M", "L"])
    }
}

import Foundation

struct FilterCriteria: Equatable {
    var sizes: Set<SizeCategory> = []
    var colors: Set<BirdColor> = []
    var families: Set<String> = []
    var searchText: String = ""

    var isEmpty: Bool {
        sizes.isEmpty && colors.isEmpty && families.isEmpty && searchText.isEmpty
    }

    var activeFilterCount: Int {
        var n = 0
        if !sizes.isEmpty { n += 1 }
        if !colors.isEmpty { n += 1 }
        if !families.isEmpty { n += 1 }
        return n
    }

    func matches(_ species: Species) -> Bool {
        if !sizes.isEmpty, !sizes.contains(species.sizeCategory) { return false }
        if !colors.isEmpty, Set(species.primaryColors).isDisjoint(with: colors) { return false }
        if !families.isEmpty, !families.contains(species.family) { return false }
        let needle = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !needle.isEmpty {
            let haystack = [species.commonName, species.scientificName, species.familyDisplayName]
                .joined(separator: " ")
                .lowercased()
            if !haystack.contains(needle) { return false }
        }
        return true
    }
}

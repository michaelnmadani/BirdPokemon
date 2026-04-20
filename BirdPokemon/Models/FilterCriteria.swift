import Foundation

struct FilterCriteria: Equatable {
    var regions: Set<Region> = []
    var sizes: Set<SizeCategory> = []
    var colors: Set<BirdColor> = []
    var families: Set<String> = []
    var searchText: String = ""

    var isEmpty: Bool {
        regions.isEmpty && sizes.isEmpty && colors.isEmpty && families.isEmpty && searchText.isEmpty
    }

    var activeFilterCount: Int {
        var n = 0
        if !regions.isEmpty { n += 1 }
        if !sizes.isEmpty { n += 1 }
        if !colors.isEmpty { n += 1 }
        if !families.isEmpty { n += 1 }
        return n
    }

    func matches(_ species: Species) -> Bool {
        if !regions.isEmpty {
            let allowed = Set(regions.map(\.rawValue))
            if allowed.isDisjoint(with: Set(species.regionCodes)) { return false }
        }
        if !sizes.isEmpty, !sizes.contains(species.sizeCategory) { return false }
        if !colors.isEmpty, Set(species.primaryColors).isDisjoint(with: colors) { return false }
        if !families.isEmpty, !families.contains(species.family) { return false }
        if !searchText.isEmpty {
            let needle = searchText.lowercased()
            let haystack = [species.commonName, species.scientificName].joined(separator: " ").lowercased()
            if !haystack.contains(needle) { return false }
        }
        return true
    }
}

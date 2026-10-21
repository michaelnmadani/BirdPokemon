import SwiftUI

/// How the collection grid is grouped. Mirrors `web/src/js/sections.js`.
enum CollectionGrouping: String, CaseIterable, Identifiable {
    case none, group, family, size, colour

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "None"
        case .group: return "Bird group"
        case .family: return "Family"
        case .size: return "Size"
        case .colour: return "Colour"
        }
    }
}

/// Picture size in the collection grid.
enum CollectionGridSize: String, CaseIterable, Identifiable {
    case small, medium, large

    var id: String { rawValue }
    var label: String { String(rawValue.prefix(1)).uppercased() }
    var minimumWidth: CGFloat {
        switch self {
        case .small: return 76
        case .medium: return 104
        case .large: return 150
        }
    }
}

struct CollectionSection: Identifiable {
    let id: String
    /// nil for the single section when the grid isn't grouped.
    let title: String?
    var emoji: String? = nil
    var swatch: BirdColor? = nil
    let species: [Species]
}

enum CollectionSections {
    /// Sections in a natural order, empty ones dropped; each species appears
    /// once. `groups` are the catalog's groups; a bird goes in the first
    /// curated group it belongs to.
    static func build(_ species: [Species], by grouping: CollectionGrouping, groups: [SpeciesGroup] = []) -> [CollectionSection] {
        switch grouping {
        case .none:
            return [CollectionSection(id: "all", title: nil, species: species)]

        case .group:
            let curated = groups.filter { $0.kind == .group }
            var first: [String: String] = [:]
            for group in curated {
                for s in group.species where first[s.ebirdCode] == nil { first[s.ebirdCode] = group.id }
            }
            let buckets = Dictionary(grouping: species) { first[$0.ebirdCode] ?? "other" }
            var ordered = curated.map { ($0.id, $0.name, $0.emoji) }
            if !ordered.contains(where: { $0.0 == "other" }) { ordered.append(("other", "Other birds", "🐤")) }
            return ordered.compactMap { id, name, emoji in
                guard let members = buckets[id] else { return nil }
                return CollectionSection(id: id, title: name, emoji: emoji, species: members)
            }

        case .family:
            // Families keep the taxonomic order the species list is already in.
            var order: [String] = []
            var buckets: [String: [Species]] = [:]
            for s in species {
                if buckets[s.familyDisplayName] == nil { order.append(s.familyDisplayName) }
                buckets[s.familyDisplayName, default: []].append(s)
            }
            return order.map { CollectionSection(id: $0, title: $0, species: buckets[$0] ?? []) }

        case .size:
            let buckets = Dictionary(grouping: species, by: \.sizeCategory)
            return SizeCategory.allCases.compactMap { size in
                guard let members = buckets[size] else { return nil }
                return CollectionSection(id: size.rawValue, title: "\(size.displayName) · \(size.approxLength)", species: members)
            }

        case .colour:
            // A bird's first listed colour is its main one.
            let buckets = Dictionary(grouping: species) { $0.primaryColors.first?.rawValue ?? "unknown" }
            var sections = BirdColor.allCases.compactMap { colour -> CollectionSection? in
                guard let members = buckets[colour.rawValue] else { return nil }
                let name = colour == .gray ? "Grey" : colour.displayName
                return CollectionSection(id: colour.rawValue, title: name, swatch: colour, species: members)
            }
            if let unknown = buckets["unknown"] {
                sections.append(CollectionSection(id: "unknown", title: "Colour not recorded", species: unknown))
            }
            return sections
        }
    }
}

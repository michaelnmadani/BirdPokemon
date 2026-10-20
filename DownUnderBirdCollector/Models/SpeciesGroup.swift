import Foundation

/// A browsable set of species: a curated bird group from `groups.json`
/// ("Flightless birds", "Parrots & cockatoos") or a genus with 2+ species
/// ("Rosellas · Platycercus"). Mirrors `web/src/js/groups.js`.
struct SpeciesGroup: Identifiable, Hashable {
    enum Kind: Hashable {
        case group
        case genus
    }

    let id: String
    let name: String
    let emoji: String
    let kind: Kind
    let genus: String?
    let species: [Species]

    var title: String { kind == .genus ? name : "\(emoji) \(name)" }

    var searchText: String { "\(name) \(genus ?? "")".lowercased() }

    static func == (lhs: SpeciesGroup, rhs: SpeciesGroup) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// One entry of `groups.json`.
struct GroupDefinition: Decodable {
    let id: String
    let name: String
    let emoji: String?
    let orders: [String]?
    let families: [String]?
    let excludeFamilies: [String]?
    let species: [String]?

    func contains(_ s: Species) -> Bool {
        if species?.contains(s.ebirdCode) == true { return true }
        if excludeFamilies?.contains(s.family) == true { return false }
        return families?.contains(s.family) == true || orders?.contains(s.order) == true
    }
}

enum SpeciesGrouping {
    /// "Black-Cockatoo" -> "Black-Cockatoos", "Finch" -> "Finches", "Goose" -> "Geese".
    static func plural(_ word: String) -> String {
        let lower = word.lowercased()
        if lower.hasSuffix("goose") { return String(word.dropLast(4)) + "eese" }
        if ["s", "x", "ch", "sh"].contains(where: lower.hasSuffix) { return word + "es" }
        if lower.hasSuffix("y"), let before = lower.dropLast().last, !"aeiou".contains(before) {
            return String(word.dropLast()) + "ies"
        }
        return word + "s"
    }

    /// Names a genus from its members' common names: "Rosellas", or the top
    /// two words when no single one covers 75% ("Ravens & Crows").
    static func genusLabel(_ commonNames: [String]) -> String {
        var counts: [String: Int] = [:]
        for name in commonNames {
            let trimmed = name.replacingOccurrences(of: #"\s*\(.*\)\s*$"#, with: "", options: .regularExpression)
            if let last = trimmed.split(separator: " ").last {
                counts[String(last), default: 0] += 1
            }
        }
        let ranked = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        guard let top = ranked.first else { return "Birds" }
        if ranked.count == 1 || Double(top.value) >= Double(commonNames.count) * 0.75 {
            return plural(top.key)
        }
        return "\(plural(top.key)) & \(plural(ranked[1].key))"
    }

    static func genus(of species: Species) -> String {
        species.scientificName.split(separator: " ").first.map(String.init) ?? ""
    }

    /// Curated groups (plus "Other birds" for anything uncovered), then genera.
    static func build(definitions: [GroupDefinition], species: [Species]) -> (groups: [SpeciesGroup], byCode: [String: [SpeciesGroup]]) {
        var groups: [SpeciesGroup] = definitions.compactMap { def in
            let members = species.filter(def.contains)
            guard !members.isEmpty else { return nil }
            return SpeciesGroup(id: def.id, name: def.name, emoji: def.emoji ?? "🐦", kind: .group, genus: nil, species: members)
        }
        let grouped = Set(groups.flatMap { $0.species.map(\.ebirdCode) })
        let others = species.filter { !grouped.contains($0.ebirdCode) }
        if !others.isEmpty {
            groups.append(SpeciesGroup(id: "other", name: "Other birds", emoji: "🐤", kind: .group, genus: nil, species: others))
        }

        var byGenus: [String: [Species]] = [:]
        var genusOrder: [String] = []
        for s in species {
            let g = genus(of: s)
            if byGenus[g] == nil { genusOrder.append(g) }
            byGenus[g, default: []].append(s)
        }
        let genera = genusOrder.compactMap { g -> SpeciesGroup? in
            guard let members = byGenus[g], members.count >= 2 else { return nil }
            return SpeciesGroup(id: "genus-\(g)", name: genusLabel(members.map(\.commonName)), emoji: "🔗",
                                kind: .genus, genus: g, species: members)
        }
        groups += genera.sorted { $0.name < $1.name }

        var byCode: [String: [SpeciesGroup]] = [:]
        for group in groups {
            for s in group.species { byCode[s.ebirdCode, default: []].append(group) }
        }
        return (groups, byCode)
    }

    static func matching(_ groups: [SpeciesGroup], query: String, limit: Int = 6) -> [SpeciesGroup] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard needle.count >= 3 else { return [] }
        return Array(groups.filter { $0.searchText.contains(needle) }.prefix(limit))
    }
}

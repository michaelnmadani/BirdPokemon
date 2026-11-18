import Foundation

/// A model class from "Dacelo novaeguineae (Laughing Kookaburra)".
struct PhotoLabel: Equatable {
    let scientificName: String
    let commonName: String
}

/// Pure helpers for photo identification, testable without the model.
/// Mirrors `web/src/js/photoid-core.js`. The model (MobileNet V2 trained on
/// iNaturalist bird photos, Google, Apache-2.0) knows ~960 species worldwide,
/// 77 of them in the Australian field guide: only those are ever suggested.
enum PhotoIDCore {
    static let inputSize = 224
    static let minConfidence = 0.05
    static let maxSuggestions = 3

    static func parseLabels(_ text: String) -> [PhotoLabel] {
        text.split(whereSeparator: \.isNewline).compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }
            if line.hasSuffix(")"), let open = line.range(of: " (") {
                return PhotoLabel(scientificName: String(line[..<open.lowerBound]),
                                  commonName: String(line[open.upperBound..<line.index(before: line.endIndex)]))
            }
            return PhotoLabel(scientificName: line, commonName: "")
        }
    }

    /// Genus + species epithet without its Latin gender ending ("moluccus" ~ "molucca").
    static func latinStem(_ scientificName: String) -> String {
        let parts = scientificName.lowercased().split(separator: " ")
        let genus = parts.first.map(String.init) ?? ""
        let epithet = parts.count > 1 ? String(parts[1]) : ""
        return "\(genus) \(epithet.replacingOccurrences(of: "(us|um|a|is|e)$", with: "", options: .regularExpression))"
    }

    private static func words(_ name: String) -> Set<String> {
        Set(name.lowercased().split { !$0.isLetter }.map(String.init))
    }

    /// For each model class, the matching field-guide species code or nil: by
    /// scientific name, then common name, then the same Latin stem when the
    /// common names share a word (Australian Ibis ~ Australian White Ibis).
    static func mapLabels(_ labels: [PhotoLabel], to species: [Species]) -> [String?] {
        var bySci: [String: Species] = [:], byCommon: [String: Species] = [:], byStem: [String: Species] = [:]
        for s in species {
            bySci[s.scientificName.lowercased()] = s
            byCommon[s.commonName.lowercased()] = s
            byStem[latinStem(s.scientificName)] = s
        }
        return labels.map { label in
            if let exact = bySci[label.scientificName.lowercased()]
                ?? (label.commonName.isEmpty ? nil : byCommon[label.commonName.lowercased()]) {
                return exact.ebirdCode
            }
            guard let stem = byStem[latinStem(label.scientificName)],
                  !words(label.commonName).isDisjoint(with: words(stem.commonName)) else { return nil }
            return stem.ebirdCode
        }
    }

    struct Result: Equatable {
        /// Field-guide species, best first: (code, confidence 0…1).
        var suggestions: [(code: String, confidence: Double)]
        /// The model's overall best guess isn't in the field guide, so it may
        /// simply not know this bird.
        var unsure: Bool

        static func == (a: Result, b: Result) -> Bool {
            a.unsure == b.unsure && a.suggestions.map(\.code) == b.suggestions.map(\.code)
                && a.suggestions.map(\.confidence) == b.suggestions.map(\.confidence)
        }
    }

    /// Model output (uint8, scale 1/256) -> probabilities.
    static func dequantize(_ bytes: [UInt8]) -> [Double] {
        bytes.map { Double($0) / 256 }
    }

    static func suggestions(_ probs: [Double], codes: [String?],
                            min: Double = minConfidence, max: Int = maxSuggestions) -> Result {
        var best = 0.0, bestKnown = 0.0
        var found: [(code: String, confidence: Double)] = []
        for (i, p) in probs.enumerated() {
            best = Swift.max(best, p)
            guard i < codes.count, let code = codes[i] else { continue }
            bestKnown = Swift.max(bestKnown, p)
            if p >= min { found.append((code, p)) }
        }
        found.sort { $0.confidence > $1.confidence }
        var seen = Set<String>()
        let unique = found.filter { seen.insert($0.code).inserted }   // several classes can map to one species
        return Result(suggestions: Array(unique.prefix(max)), unsure: best > bestKnown)
    }
}

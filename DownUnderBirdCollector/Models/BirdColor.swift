import Foundation
import SwiftUI

/// Must stay in sync with `COLORS` in `scripts/seed-ebird/lib/bundle.ts`
/// and `web/src/js/model.js`.
enum BirdColor: String, CaseIterable, Codable, Identifiable {
    case red
    case orange
    case yellow
    case green
    case blue
    case brown
    case black
    case white
    case gray
    case pink
    case purple

    var id: String { rawValue }

    var displayName: String { rawValue.capitalized }

    var swiftUIColor: Color {
        switch self {
        case .red:    return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green:  return .green
        case .blue:   return .blue
        case .brown:  return Color(red: 0.55, green: 0.35, blue: 0.18)
        case .black:  return .black
        case .white:  return .white
        case .gray:   return .gray
        case .pink:   return .pink
        case .purple: return .purple
        }
    }

    /// Accepts field-guide plumage words ("rufous", "grey") and folds them onto
    /// the app's palette. Returns nil for words that aren't colours at all.
    init?(lenient value: String) {
        let key = value.trimmingCharacters(in: .whitespaces).lowercased()
        if let exact = BirdColor(rawValue: key) {
            self = exact
        } else if let mapped = Self.aliases[key] {
            self = mapped
        } else {
            return nil
        }
    }

    /// Mirrors `COLOR_ALIASES` in `scripts/seed-ebird/lib/bundle.ts`.
    static let aliases: [String: BirdColor] = [
        "grey": .gray,
        "buff": .brown,
        "rufous": .orange,
        "chestnut": .brown,
        "tawny": .brown,
        "cinnamon": .brown,
        "olive": .green,
        "bronze": .green,
        "crimson": .red,
        "scarlet": .red,
        "gold": .yellow,
        "plum": .purple,
        "violet": .purple,
    ]
}

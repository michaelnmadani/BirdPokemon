import Foundation
import SwiftUI

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
}

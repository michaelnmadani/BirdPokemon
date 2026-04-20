import Foundation

enum Region: String, CaseIterable, Codable, Identifiable {
    case australia = "AU"
    case newZealand = "NZ"
    case unitedKingdom = "GB"
    case unitedStates = "US"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .australia: return "Australia"
        case .newZealand: return "New Zealand"
        case .unitedKingdom: return "United Kingdom"
        case .unitedStates: return "United States"
        }
    }

    var flag: String {
        switch self {
        case .australia: return "🇦🇺"
        case .newZealand: return "🇳🇿"
        case .unitedKingdom: return "🇬🇧"
        case .unitedStates: return "🇺🇸"
        }
    }

    static let shippedAtLaunch: [Region] = [.australia]
}

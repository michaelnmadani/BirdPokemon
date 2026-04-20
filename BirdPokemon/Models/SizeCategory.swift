import Foundation

enum SizeCategory: String, CaseIterable, Codable, Identifiable {
    case tiny
    case small
    case medium
    case large
    case huge

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tiny:   return "Tiny"
        case .small:  return "Small"
        case .medium: return "Medium"
        case .large:  return "Large"
        case .huge:   return "Huge"
        }
    }

    var approxLength: String {
        switch self {
        case .tiny:   return "< 10 cm"
        case .small:  return "10 – 20 cm"
        case .medium: return "20 – 35 cm"
        case .large:  return "35 – 60 cm"
        case .huge:   return "> 60 cm"
        }
    }

    /// Bucket a species by body length in centimetres. Falls back to `.medium`
    /// when length is missing — the app should hide the size filter for that
    /// species rather than mislabel it.
    static func bucket(lengthCm: Double?) -> SizeCategory {
        guard let cm = lengthCm else { return .medium }
        switch cm {
        case ..<10:  return .tiny
        case ..<20:  return .small
        case ..<35:  return .medium
        case ..<60:  return .large
        default:     return .huge
        }
    }
}

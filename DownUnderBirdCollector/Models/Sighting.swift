import Foundation
import CoreLocation

/// A bird the user photographed. Stored as JSON on device, or as a Firestore
/// document when cloud sync is enabled — the same shape works for both.
struct Sighting: Identifiable, Codable, Hashable {
    enum LocationSource: String, Codable {
        case device   // GPS fix taken when the sighting was saved
        case photo    // read from the photo's own metadata
    }

    var id: String
    var userId: String

    var speciesCode: String
    var speciesCommonName: String
    var speciesSciName: String

    var capturedAt: Date
    var createdAt: Date

    var latitude: Double?
    var longitude: Double?
    var locationAccuracy: Double?
    var locationSource: LocationSource?

    var notes: String?

    var mlTopPrediction: String?
    var mlTopConfidence: Double?
    var userOverrode: Bool

    // On-device copies (file names inside the store's photo folder).
    var localPhotoFile: String?
    var localThumbnailFile: String?

    // Cloud copies (only set when cloud sync is on).
    var photoURL: String?
    var thumbnailURL: String?
    var photoStoragePath: String?
    var thumbnailStoragePath: String?

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// Everything needed to create a sighting; the store assigns ids and files.
struct SightingDraft {
    var species: Species
    /// nil when the bird was logged without a photo (seen or heard).
    var photo: CapturedPhoto?
    var capturedAt: Date
    var coordinate: CLLocationCoordinate2D?
    var locationAccuracy: Double?
    var locationSource: Sighting.LocationSource?
    var notes: String?
    var mlTopPrediction: Prediction?

    var userOverrode: Bool {
        guard let top = mlTopPrediction else { return false }
        return top.speciesCode != species.ebirdCode
    }
}

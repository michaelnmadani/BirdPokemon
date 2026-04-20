import Foundation
import FirebaseFirestore
import CoreLocation

struct Sighting: Identifiable, Codable, Hashable {
    @DocumentID var documentID: String?

    let userId: String
    let speciesCode: String
    let speciesCommonName: String
    let speciesSciName: String

    let photoURL: String
    let photoStoragePath: String
    let thumbnailURL: String?

    let latitude: Double
    let longitude: Double
    let geohash: String?
    let locationName: String?

    let capturedAt: Date
    let notes: String?

    let mlTopPrediction: String?
    let mlTopConfidence: Double?
    let userOverrode: Bool

    @ServerTimestamp var createdAt: Date?

    var id: String { documentID ?? UUID().uuidString }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

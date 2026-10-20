import UIKit
import CoreLocation

/// A photo waiting to become a sighting, plus whatever the photo itself
/// told us about when and where it was taken.
struct CapturedPhoto: Identifiable {
    enum Source {
        case camera
        case library
    }

    let id = UUID()
    let image: UIImage
    let source: Source
    var takenAt: Date?
    var coordinate: CLLocationCoordinate2D?

    init(image: UIImage, source: Source, takenAt: Date? = nil, coordinate: CLLocationCoordinate2D? = nil) {
        self.image = image
        self.source = source
        self.takenAt = takenAt
        self.coordinate = coordinate
    }

    /// Builds a photo from picked image data, reading EXIF date and GPS.
    init?(libraryData data: Data) {
        guard let image = UIImage(data: data) else { return nil }
        let metadata = ImageProcessing.metadata(from: data)
        self.init(image: image, source: .library, takenAt: metadata.takenAt, coordinate: metadata.coordinate)
    }
}

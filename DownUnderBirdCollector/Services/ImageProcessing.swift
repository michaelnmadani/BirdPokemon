import UIKit
import ImageIO
import CoreLocation

/// The two JPEGs stored for every sighting.
struct ProcessedPhoto {
    let full: Data
    let thumbnail: Data
}

enum ImageProcessing {
    static let fullMaxDimension: CGFloat = 2048
    static let thumbnailMaxDimension: CGFloat = 400

    enum ProcessingError: LocalizedError {
        case encodingFailed

        var errorDescription: String? { "Couldn't prepare the photo for saving." }
    }

    /// Scales `image` so its longest side is at most `maxDimension` pixels.
    /// Always redraws, which also bakes in the EXIF orientation.
    static func resized(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let longest = max(pixelWidth, pixelHeight)
        let factor = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(width: (pixelWidth * factor).rounded(), height: (pixelHeight * factor).rounded())

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// Downscales and encodes a photo plus thumbnail. Re-encoding also strips
    /// the original EXIF (including GPS) from the stored files.
    static func process(_ image: UIImage) throws -> ProcessedPhoto {
        guard
            let full = resized(image, maxDimension: fullMaxDimension).jpegData(compressionQuality: 0.85),
            let thumbnail = resized(image, maxDimension: thumbnailMaxDimension).jpegData(compressionQuality: 0.8)
        else {
            throw ProcessingError.encodingFailed
        }
        return ProcessedPhoto(full: full, thumbnail: thumbnail)
    }

    /// Reads the capture date and GPS position embedded in image data.
    static func metadata(from data: Data) -> (takenAt: Date?, coordinate: CLLocationCoordinate2D?) {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            return (nil, nil)
        }
        return (takenAt(from: properties), coordinate(from: properties))
    }

    private static func coordinate(from properties: [CFString: Any]) -> CLLocationCoordinate2D? {
        guard
            let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
            var latitude = gps[kCGImagePropertyGPSLatitude] as? Double,
            var longitude = gps[kCGImagePropertyGPSLongitude] as? Double
        else {
            return nil
        }
        if (gps[kCGImagePropertyGPSLatitudeRef] as? String)?.uppercased() == "S" { latitude = -latitude }
        if (gps[kCGImagePropertyGPSLongitudeRef] as? String)?.uppercased() == "W" { longitude = -longitude }
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
    }

    private static func takenAt(from properties: [CFString: Any]) -> Date? {
        guard
            let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
            let stamp = exif[kCGImagePropertyExifDateTimeOriginal] as? String
        else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if let offset = exif[kCGImagePropertyExifOffsetTimeOriginal] as? String {
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ssxxx"
            if let date = formatter.date(from: stamp + offset) { return date }
        }
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.timeZone = .current
        return formatter.date(from: stamp)
    }
}

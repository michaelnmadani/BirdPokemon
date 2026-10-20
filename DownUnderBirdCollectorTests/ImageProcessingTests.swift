import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import DownUnderBirdCollector

final class ImageProcessingTests: XCTestCase {
    func testResizeCapsLongestSide() {
        let resized = ImageProcessing.resized(TestFixtures.image(width: 4000, height: 3000), maxDimension: 2048)
        XCTAssertEqual(resized.size.width, 2048)
        XCTAssertEqual(resized.size.height, 1536)
    }

    func testResizeNeverUpscales() {
        let resized = ImageProcessing.resized(TestFixtures.image(width: 300, height: 200), maxDimension: 2048)
        XCTAssertEqual(resized.size, CGSize(width: 300, height: 200))
    }

    func testReadsGPSAndDateFromExif() throws {
        let data = try jpeg(withGPS: (lat: 27.4698, latRef: "S", lon: 153.0251, lonRef: "E"),
                            date: "2025:09:14 07:30:00")
        let metadata = ImageProcessing.metadata(from: data)
        let coordinate = try XCTUnwrap(metadata.coordinate)
        XCTAssertEqual(coordinate.latitude, -27.4698, accuracy: 0.0001)
        XCTAssertEqual(coordinate.longitude, 153.0251, accuracy: 0.0001)
        // Without an EXIF offset the timestamp is read as device-local time.
        var components = DateComponents(year: 2025, month: 9, day: 14, hour: 7, minute: 30)
        components.timeZone = .current
        XCTAssertEqual(metadata.takenAt, Calendar(identifier: .gregorian).date(from: components))
    }

    func testMissingMetadataIsNil() throws {
        let data = try XCTUnwrap(TestFixtures.image(width: 10, height: 10).jpegData(compressionQuality: 0.8))
        let metadata = ImageProcessing.metadata(from: data)
        XCTAssertNil(metadata.coordinate)
        XCTAssertNil(metadata.takenAt)
    }

    private func jpeg(withGPS gps: (lat: Double, latRef: String, lon: Double, lonRef: String),
                      date: String) throws -> Data {
        let cgImage = try XCTUnwrap(TestFixtures.image(width: 10, height: 10).cgImage)
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil))
        let properties: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: gps.lat,
                kCGImagePropertyGPSLatitudeRef: gps.latRef,
                kCGImagePropertyGPSLongitude: gps.lon,
                kCGImagePropertyGPSLongitudeRef: gps.lonRef,
            ],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: date,
            ],
        ]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }
}

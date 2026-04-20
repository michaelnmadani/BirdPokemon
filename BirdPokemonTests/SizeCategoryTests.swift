import XCTest
@testable import BirdPokemon

final class SizeCategoryTests: XCTestCase {
    func testBucketBoundaries() {
        XCTAssertEqual(SizeCategory.bucket(lengthCm: 8), .tiny)
        XCTAssertEqual(SizeCategory.bucket(lengthCm: 10), .small)
        XCTAssertEqual(SizeCategory.bucket(lengthCm: 19.9), .small)
        XCTAssertEqual(SizeCategory.bucket(lengthCm: 20), .medium)
        XCTAssertEqual(SizeCategory.bucket(lengthCm: 34.9), .medium)
        XCTAssertEqual(SizeCategory.bucket(lengthCm: 35), .large)
        XCTAssertEqual(SizeCategory.bucket(lengthCm: 59.9), .large)
        XCTAssertEqual(SizeCategory.bucket(lengthCm: 60), .huge)
        XCTAssertEqual(SizeCategory.bucket(lengthCm: 150), .huge)
    }

    func testNilFallsBackToMedium() {
        XCTAssertEqual(SizeCategory.bucket(lengthCm: nil), .medium)
    }
}

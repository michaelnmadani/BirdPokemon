import XCTest
import CoreLocation
@testable import DownUnderBirdCollector

final class NearbySummaryTests: XCTestCase {
    private let sydney = CLLocationCoordinate2D(latitude: -33.8688, longitude: 151.2093)

    private func sighting(_ id: String, code: String, lat: Double?, lon: Double?, at seconds: TimeInterval = 0) -> Sighting {
        Sighting(id: id, userId: "local", speciesCode: code, speciesCommonName: code.capitalized, speciesSciName: "",
                 capturedAt: Date(timeIntervalSince1970: 1_790_000_000 + seconds), createdAt: Date(),
                 latitude: lat, longitude: lon, userOverrode: false)
    }

    private func report(_ code: String, lat: Double, lng: Double, date: String) -> EBirdObservation {
        EBirdObservation(speciesCode: code, comName: code.capitalized, sciName: "", locName: "Park",
                         obsDt: date, howMany: 1, lat: lat, lng: lng)
    }

    func testDistance() {
        let brisbane = CLLocationCoordinate2D(latitude: -27.4698, longitude: 153.0251)
        XCTAssertEqual(NearbySummary.distanceKm(sydney, brisbane), 730, accuracy: 10)
    }

    func testOnlySightingsWithinRadiusCount() {
        let list = [
            sighting("near", code: "galah", lat: -33.87, lon: 151.21),
            sighting("edge", code: "galah", lat: -33.9118, lon: 151.2093),   // ~4.8 km
            sighting("far", code: "emu1", lat: -33.95, lon: 151.2093),       // ~9 km
            sighting("nowhere", code: "emu1", lat: nil, lon: nil),
        ]
        XCTAssertEqual(NearbySummary.sightings(list, within: 5, of: sydney).map(\.id), ["near", "edge"])
    }

    func testEntriesMergeSightingsAndReports() {
        let galah = TestFixtures.species(code: "galah", name: "Galah")
        let entries = NearbySummary.entries(
            center: sydney,
            mine: [sighting("a", code: "galah", lat: -33.87, lon: 151.21)],
            reports: [
                report("galah", lat: -33.87, lng: 151.2, date: "2027-01-10 08:00"),
                report("other1", lat: -33.87, lng: 151.2, date: "2027-01-12"),
                report("far1", lat: -30, lng: 150, date: "2027-01-12"),
            ],
            lookup: { $0 == "galah" ? galah : nil }
        )
        XCTAssertEqual(entries.map(\.code), ["other1", "galah"])
        XCTAssertEqual(entries.last?.mine.count, 1)
        XCTAssertEqual(entries.last?.report?.obsDt, "2027-01-10 08:00")
        XCTAssertNotNil(entries.last?.species)
        XCTAssertNil(entries.first?.species)
    }

    func testDecodesEBirdResponse() throws {
        let json = """
        [{"speciesCode":"rainbowlor1","comName":"Rainbow Lorikeet","sciName":"Trichoglossus moluccanus",
          "locId":"L1","locName":"Hyde Park","obsDt":"2026-10-18 08:15","howMany":12,"lat":-33.873,"lng":151.211,
          "obsValid":true,"obsReviewed":false,"locationPrivate":false,"subId":"S1"},
         {"speciesCode":"auwhib1","comName":"Australian White Ibis","sciName":"Threskiornis molucca",
          "obsDt":"2026-10-19","lat":-33.866,"lng":151.216}]
        """
        let reports = try JSONDecoder().decode([EBirdObservation].self, from: Data(json.utf8))
        XCTAssertEqual(reports.count, 2)
        XCTAssertEqual(reports[0].howMany, 12)
        XCTAssertNil(reports[1].howMany)
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour], from: reports[0].observedAt)
        XCTAssertEqual(components.day, 18)
        XCTAssertEqual(components.hour, 8)
        XCTAssertEqual(Calendar.current.component(.day, from: reports[1].observedAt), 19)
    }

    func testDaysAgo() {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 12))!
        XCTAssertEqual(NearbySummary.daysAgo(calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 6))!, now: now, calendar: calendar), "today")
        XCTAssertEqual(NearbySummary.daysAgo(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 23))!, now: now, calendar: calendar), "yesterday")
        XCTAssertEqual(NearbySummary.daysAgo(calendar.date(from: DateComponents(year: 2026, month: 10, day: 17))!, now: now, calendar: calendar), "3 days ago")
    }
}

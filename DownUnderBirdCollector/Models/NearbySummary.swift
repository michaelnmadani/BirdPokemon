import Foundation
import CoreLocation

/// One species spotted near a point: your own sightings there and/or the
/// latest eBird report. Mirrors `web/src/js/nearby.js`.
struct NearbyEntry: Identifiable {
    let code: String
    let name: String
    let scientificName: String
    let species: Species?
    var mine: [Sighting] = []
    var report: EBirdObservation?
    var lastSeen: Date = .distantPast

    var id: String { code }
}

enum NearbySummary {
    static let radiusKm: Double = 5

    static func distanceKm(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude)) / 1000
    }

    static func sightings(_ sightings: [Sighting], within km: Double, of center: CLLocationCoordinate2D) -> [Sighting] {
        sightings.filter { sighting in
            guard let coordinate = sighting.coordinate else { return false }
            return distanceKm(center, coordinate) <= km
        }
    }

    /// One entry per species, most recently seen first.
    static func entries(center: CLLocationCoordinate2D,
                        km: Double = radiusKm,
                        mine: [Sighting],
                        reports: [EBirdObservation],
                        lookup: (String) -> Species?) -> [NearbyEntry] {
        var byCode: [String: NearbyEntry] = [:]
        var order: [String] = []

        func update(_ code: String, name: String, sciName: String, _ change: (inout NearbyEntry) -> Void) {
            if byCode[code] == nil {
                byCode[code] = NearbyEntry(code: code, name: name, scientificName: sciName, species: lookup(code))
                order.append(code)
            }
            change(&byCode[code]!)
        }

        for sighting in sightings(mine, within: km, of: center) {
            update(sighting.speciesCode, name: sighting.speciesCommonName, sciName: sighting.speciesSciName) { entry in
                entry.mine.append(sighting)
                entry.lastSeen = max(entry.lastSeen, sighting.capturedAt)
            }
        }
        for report in reports {
            if let lat = report.lat, let lng = report.lng,
               distanceKm(center, CLLocationCoordinate2D(latitude: lat, longitude: lng)) > km {
                continue
            }
            update(report.speciesCode, name: report.comName, sciName: report.sciName) { entry in
                if entry.report == nil || report.observedAt > entry.report!.observedAt { entry.report = report }
                entry.lastSeen = max(entry.lastSeen, report.observedAt)
            }
        }
        return order.compactMap { byCode[$0] }.sorted {
            $0.lastSeen != $1.lastSeen ? $0.lastSeen > $1.lastSeen : $0.name < $1.name
        }
    }

    /// "today", "yesterday", "3 days ago".
    static func daysAgo(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ...0: return "today"
        case 1: return "yesterday"
        default: return "\(days) days ago"
        }
    }
}

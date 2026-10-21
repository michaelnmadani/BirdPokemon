import Foundation

/// One eBird report from `data/obs/geo/recent`.
struct EBirdObservation: Codable, Hashable {
    let speciesCode: String
    let comName: String
    let sciName: String
    let locName: String?
    let obsDt: String
    let howMany: Int?
    let lat: Double?
    let lng: Double?

    /// eBird reports local time at the site, e.g. "2026-10-18 08:15".
    var observedAt: Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = obsDt.count > 10 ? "yyyy-MM-dd HH:mm" : "yyyy-MM-dd"
        return formatter.date(from: obsDt) ?? .distantPast
    }
}

/// Recent eBird reports near a point. Needs a free personal API key
/// (https://ebird.org/api/keygen), entered in Settings or set as
/// `EBIRD_API_KEY` in Secrets.xcconfig. The last result is cached so the
/// Nearby tab still shows something offline.
enum EBirdClient {
    static let apiKeyDefaultsKey = "ebirdAPIKey"
    private static let cacheDefaultsKey = "ebirdNearbyCache"

    enum EBirdError: LocalizedError {
        case missingKey
        case rejectedKey
        case badStatus(Int)
        case offline

        var errorDescription: String? {
            switch self {
            case .missingKey: return "No eBird API key."
            case .rejectedKey: return "eBird rejected the API key — check it in Settings."
            case .badStatus(let code): return "eBird returned an error (\(code))."
            case .offline: return "Couldn't reach eBird — you may be offline."
            }
        }
    }

    struct Result {
        let reports: [EBirdObservation]
        let fetchedAt: Date
        let cached: Bool
    }

    private struct Cache: Codable {
        let latitude: Double
        let longitude: Double
        let fetchedAt: Date
        let reports: [EBirdObservation]
    }

    /// The key from Settings, else the build-time one, else nil.
    static func apiKey(defaults: UserDefaults = .standard) -> String? {
        let stored = defaults.string(forKey: apiKeyDefaultsKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let stored, !stored.isEmpty { return stored }
        let bundled = (Bundle.main.object(forInfoDictionaryKey: "EBirdAPIKey") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (bundled?.isEmpty == false && bundled?.hasPrefix("$(") == false) ? bundled : nil
    }

    static func recentNearby(latitude: Double, longitude: Double, km: Double, days: Int = 30,
                             session: URLSession = .shared, defaults: UserDefaults = .standard) async throws -> Result {
        guard let key = apiKey(defaults: defaults) else { throw EBirdError.missingKey }
        var components = URLComponents(string: "https://api.ebird.org/v2/data/obs/geo/recent")!
        components.queryItems = [
            // Rounded to ~1 km: plenty for a 5 km search, and less precise than your actual spot.
            URLQueryItem(name: "lat", value: String(format: "%.2f", latitude)),
            URLQueryItem(name: "lng", value: String(format: "%.2f", longitude)),
            // +1 km covers the rounding; NearbySummary keeps only reports within `km` of you.
            URLQueryItem(name: "dist", value: String(Int(km) + 1)),
            URLQueryItem(name: "back", value: String(days)),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(key, forHTTPHeaderField: "X-eBirdApiToken")

        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 || status == 403 { throw EBirdError.rejectedKey }
            guard (200..<300).contains(status) else { throw EBirdError.badStatus(status) }
            let reports = try JSONDecoder().decode([EBirdObservation].self, from: data)
            let now = Date()
            let cache = Cache(latitude: latitude, longitude: longitude, fetchedAt: now, reports: reports)
            defaults.set(try? JSONEncoder().encode(cache), forKey: cacheDefaultsKey)
            return Result(reports: reports, fetchedAt: now, cached: false)
        } catch let error as EBirdError {
            if case .rejectedKey = error { throw error }
            if let cached = cached(near: latitude, longitude, defaults: defaults) { return cached }
            throw error
        } catch {
            if let cached = cached(near: latitude, longitude, defaults: defaults) { return cached }
            throw EBirdError.offline
        }
    }

    /// The last result, if it was fetched for roughly the same place.
    private static func cached(near latitude: Double, _ longitude: Double, defaults: UserDefaults) -> Result? {
        guard
            let data = defaults.data(forKey: cacheDefaultsKey),
            let cache = try? JSONDecoder().decode(Cache.self, from: data),
            abs(cache.latitude - latitude) < 0.02, abs(cache.longitude - longitude) < 0.02
        else { return nil }
        return Result(reports: cache.reports, fetchedAt: cache.fetchedAt, cached: true)
    }
}

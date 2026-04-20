import Foundation

/// Minimal async URLSession client for the eBird 2.0 API.
/// https://documenter.getpostman.com/view/664302/S1ENwy59
///
/// Used primarily by the admin seed scripts, but available in-app for the
/// optional "recent obs near me" feature.
struct EBirdAPI {
    enum APIError: Error {
        case missingAPIKey
        case invalidURL
        case badStatus(Int)
    }

    private let baseURL = URL(string: "https://api.ebird.org/v2/")!
    private let session: URLSession
    private let apiKey: String?

    init(session: URLSession = .shared,
         apiKey: String? = Bundle.main.object(forInfoDictionaryKey: "EBirdAPIKey") as? String) {
        self.session = session
        self.apiKey = apiKey
    }

    func taxonomy(locale: String = "en") async throws -> Data {
        try await get(path: "ref/taxonomy/ebird", query: [
            "fmt": "json",
            "locale": locale
        ])
    }

    func regionalSpeciesList(regionCode: String) async throws -> [String] {
        let data = try await get(path: "product/spplist/\(regionCode)")
        return try JSONDecoder().decode([String].self, from: data)
    }

    func recentObservations(regionCode: String, days: Int = 7) async throws -> Data {
        try await get(path: "data/obs/\(regionCode)/recent", query: [
            "back": String(days)
        ])
    }

    private func get(path: String, query: [String: String] = [:]) async throws -> Data {
        guard let apiKey, !apiKey.isEmpty, apiKey != "replace_me_with_real_key" else {
            throw APIError.missingAPIKey
        }
        var comps = URLComponents(url: baseURL.appendingPathComponent(path),
                                  resolvingAgainstBaseURL: false)
        comps?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = comps?.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.addValue(apiKey, forHTTPHeaderField: "X-eBirdApiToken")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.badStatus(-1) }
        guard (200..<300).contains(http.statusCode) else { throw APIError.badStatus(http.statusCode) }
        return data
    }
}

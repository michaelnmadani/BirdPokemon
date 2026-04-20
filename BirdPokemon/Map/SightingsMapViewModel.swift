import Foundation
import MapKit

@MainActor
final class SightingsMapViewModel: ObservableObject {
    @Published private(set) var sightings: [Sighting] = []
    @Published var cameraPosition: MapCameraPosition = .automatic

    private let repo = SightingsRepository()
    private var streamTask: Task<Void, Never>?

    deinit { streamTask?.cancel() }

    func start(uid: String) {
        streamTask?.cancel()
        streamTask = Task {
            do {
                for try await sightings in repo.stream(uid: uid) {
                    self.sightings = sightings
                    self.recenter()
                }
            } catch {
                print("Map stream error: \(error)")
            }
        }
    }

    private func recenter() {
        guard !sightings.isEmpty else { return }
        let lats = sightings.map(\.latitude)
        let lons = sightings.map(\.longitude)
        let minLat = lats.min() ?? 0
        let maxLat = lats.max() ?? 0
        let minLon = lons.min() ?? 0
        let maxLon = lons.max() ?? 0
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.05, (maxLat - minLat) * 1.4),
            longitudeDelta: max(0.05, (maxLon - minLon) * 1.4)
        )
        cameraPosition = .region(.init(center: center, span: span))
    }
}

import Foundation
import CoreLocation

@MainActor
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum Status {
        case unknown
        case denied
        case authorized
    }

    @Published private(set) var status: Status = .unknown
    @Published private(set) var lastLocation: CLLocation?

    private let manager = CLLocationManager()
    private var oneShotContinuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        syncStatus()
    }

    func requestWhenInUse() {
        manager.requestWhenInUseAuthorization()
    }

    /// One-shot fix — returns the first acceptable location or throws.
    func currentLocation(timeout: TimeInterval = 12) async throws -> CLLocation {
        if status != .authorized {
            manager.requestWhenInUseAuthorization()
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.oneShotContinuation = continuation
            self.manager.requestLocation()

            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                guard let self, let cont = self.oneShotContinuation else { return }
                self.oneShotContinuation = nil
                cont.resume(throwing: CLError(.locationUnknown))
            }
        }
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.syncStatus() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            self.lastLocation = loc
            if let cont = self.oneShotContinuation {
                self.oneShotContinuation = nil
                cont.resume(returning: loc)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            if let cont = self.oneShotContinuation {
                self.oneShotContinuation = nil
                cont.resume(throwing: error)
            }
        }
    }

    private func syncStatus() {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            status = .authorized
        case .denied, .restricted:
            status = .denied
        case .notDetermined:
            status = .unknown
        @unknown default:
            status = .unknown
        }
    }
}

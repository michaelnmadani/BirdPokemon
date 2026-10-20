import Foundation
import CoreLocation

@MainActor
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum Status {
        case notDetermined
        case denied
        case authorized
    }

    enum LocationError: LocalizedError {
        case denied
        case timedOut

        var errorDescription: String? {
            switch self {
            case .denied: return "Location access is off for this app. You can turn it on in Settings."
            case .timedOut: return "Couldn't get a GPS fix. Try again with a clearer view of the sky."
            }
        }
    }

    @Published private(set) var status: Status = .notDetermined
    @Published private(set) var lastLocation: CLLocation?

    private let manager = CLLocationManager()
    private var pending: [UUID: CheckedContinuation<CLLocation, Error>] = [:]
    private var authorizationWaiters: [CheckedContinuation<Void, Never>] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        syncStatus()
    }

    func requestPermissionIfNeeded() {
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    /// A single fix. Reuses a recent one if available; concurrent callers
    /// share the same request.
    func currentLocation(timeout: TimeInterval = 15, maxAge: TimeInterval = 60) async throws -> CLLocation {
        if let last = lastLocation, -last.timestamp.timeIntervalSinceNow < maxAge {
            return last
        }
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
            await withCheckedContinuation { authorizationWaiters.append($0) }
        }
        guard status == .authorized else { throw LocationError.denied }

        let id = UUID()
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            if pending.count == 1 {
                manager.requestLocation()
            }
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self?.pending.removeValue(forKey: id)?.resume(throwing: LocationError.timedOut)
            }
        }
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.syncStatus() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.lastLocation = location
            self.finishAll(.success(location))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            // kCLErrorLocationUnknown is transient; Core Location keeps trying.
            if (error as? CLError)?.code == .locationUnknown { return }
            self.finishAll(.failure(error))
        }
    }

    private func finishAll(_ result: Result<CLLocation, Error>) {
        let waiting = pending.values
        pending.removeAll()
        for continuation in waiting {
            continuation.resume(with: result)
        }
    }

    private func syncStatus() {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            status = .authorized
        case .denied, .restricted:
            status = .denied
        case .notDetermined:
            status = .notDetermined
        @unknown default:
            status = .notDetermined
        }
        if status != .notDetermined {
            let waiters = authorizationWaiters
            authorizationWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
    }
}

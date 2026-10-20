import Foundation
import FirebaseAuth

@MainActor
final class AppState: ObservableObject {
    enum Mode: Equatable {
        /// Sightings stay on this device; no account.
        case local
        /// Firebase sign-in and sync (a GoogleService-Info.plist is bundled).
        case cloud
    }

    enum AuthStatus: Equatable {
        case unknown
        case signedOut
        case signedIn(uid: String)
    }

    let mode: Mode
    let sightings: SightingStore

    @Published private(set) var authStatus: AuthStatus = .unknown
    @Published private(set) var accountEmail: String?
    @Published var selectedRegion: Region {
        didSet { defaults.set(selectedRegion.rawValue, forKey: Self.regionKey) }
    }

    private let defaults: UserDefaults
    private let authService = AuthService()
    // AppState lives for the whole app run, so the listener is never removed.
    private var authHandle: AuthStateDidChangeListenerHandle?
    private static let regionKey = "selectedRegion"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.selectedRegion = defaults.string(forKey: Self.regionKey).flatMap(Region.init(rawValue:)) ?? .australia
        self.mode = CloudConfig.configureIfAvailable() ? .cloud : .local
        self.sightings = SightingStore()

        switch mode {
        case .local:
            startLocal()
        case .cloud:
            observeAuth()
        }
    }

    // MARK: - Local mode

    private func startLocal() {
        do {
            let directory = try LocalSightingBackend.defaultDirectory()
            sightings.attach(LocalSightingBackend(directory: directory))
        } catch {
            sightings.lastError = error.localizedDescription
        }
        authStatus = .signedIn(uid: LocalSightingBackend.localUserId)
    }

    // MARK: - Cloud mode

    private func observeAuth() {
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let user {
                    self.accountEmail = user.email
                    if self.authStatus != .signedIn(uid: user.uid) {
                        self.sightings.attach(FirebaseSightingBackend(uid: user.uid))
                        self.authStatus = .signedIn(uid: user.uid)
                    }
                } else {
                    self.accountEmail = nil
                    self.sightings.attach(nil)
                    self.authStatus = .signedOut
                }
            }
        }
    }

    func signOut() {
        guard mode == .cloud else { return }
        do {
            try authService.signOut()
        } catch {
            sightings.lastError = error.localizedDescription
        }
    }

    /// Deletes every sighting (and its photos), then the account itself in
    /// cloud mode. Required by App Store guideline 5.1.1(v).
    func deleteAllData() async throws {
        try await sightings.deleteAll()
        if mode == .cloud {
            try await authService.deleteCurrentUser()
        }
    }
}

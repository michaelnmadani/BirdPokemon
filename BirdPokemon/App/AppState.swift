import Foundation
import Combine
import FirebaseAuth

@MainActor
final class AppState: ObservableObject {
    enum AuthStatus: Equatable {
        case unknown
        case signedOut
        case signedIn(uid: String)
    }

    @Published var authStatus: AuthStatus = .unknown
    @Published var currentUser: AppUser?
    @Published var selectedRegion: Region = .australia

    private var authHandle: AuthStateDidChangeListenerHandle?
    private let userRepository: UserRepository

    init(userRepository: UserRepository = UserRepository()) {
        self.userRepository = userRepository
        observeAuth()
    }

    deinit {
        if let handle = authHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    private func observeAuth() {
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            Task { @MainActor in
                if let user {
                    self.authStatus = .signedIn(uid: user.uid)
                    await self.refreshCurrentUser(uid: user.uid,
                                                  displayName: user.displayName,
                                                  email: user.email)
                } else {
                    self.authStatus = .signedOut
                    self.currentUser = nil
                }
            }
        }
    }

    func refreshCurrentUser(uid: String, displayName: String?, email: String?) async {
        do {
            let user = try await userRepository.ensureUser(
                uid: uid,
                displayName: displayName,
                email: email
            )
            self.currentUser = user
            if let region = user.homeRegion {
                self.selectedRegion = region
            }
        } catch {
            print("AppState: failed to load user doc — \(error)")
        }
    }

    func updateHomeRegion(_ region: Region) async {
        guard let uid = currentUser?.uid else { return }
        selectedRegion = region
        do {
            try await userRepository.updateHomeRegion(uid: uid, region: region)
            currentUser?.homeRegionCode = region.rawValue
        } catch {
            print("AppState: failed to update home region — \(error)")
        }
    }
}

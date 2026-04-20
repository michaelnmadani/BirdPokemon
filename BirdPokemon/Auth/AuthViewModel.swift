import Foundation
import AuthenticationServices

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var email: String = ""
    @Published var password: String = ""
    @Published var displayName: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let authService = AuthService()

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        authService.prepareAppleRequest(request)
    }

    func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) async {
        isLoading = true
        defer { isLoading = false }
        do {
            _ = try await authService.handleAppleCompletion(result)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signIn() async {
        isLoading = true
        defer { isLoading = false }
        do {
            _ = try await authService.signIn(email: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signUp() async {
        isLoading = true
        defer { isLoading = false }
        do {
            _ = try await authService.signUp(
                email: email,
                password: password,
                displayName: displayName.isEmpty ? nil : displayName
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func sendPasswordReset() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await authService.sendPasswordReset(email: email)
            errorMessage = "Password reset email sent."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        do {
            try authService.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

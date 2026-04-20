import Foundation
import FirebaseAuth
import AuthenticationServices
import CryptoKit

@MainActor
final class AuthService: NSObject {
    enum AuthError: LocalizedError {
        case appleNonceUnavailable
        case appleCredentialMissing
        case appleIdentityTokenMissing
        case appleIdentityTokenDecodeFailed

        var errorDescription: String? {
            switch self {
            case .appleNonceUnavailable: return "Could not prepare Sign in with Apple request."
            case .appleCredentialMissing: return "Apple didn't return a credential."
            case .appleIdentityTokenMissing: return "Apple didn't return an identity token."
            case .appleIdentityTokenDecodeFailed: return "Couldn't decode Apple's identity token."
            }
        }
    }

    // MARK: - Email / Password

    func signUp(email: String, password: String, displayName: String?) async throws -> User {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        if let displayName, !displayName.isEmpty {
            let change = result.user.createProfileChangeRequest()
            change.displayName = displayName
            try await change.commitChanges()
        }
        return result.user
    }

    func signIn(email: String, password: String) async throws -> User {
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        return result.user
    }

    func sendPasswordReset(email: String) async throws {
        try await Auth.auth().sendPasswordReset(withEmail: email)
    }

    // MARK: - Sign in with Apple

    private var currentAppleNonce: String?

    /// Call from the SIWA button's `onRequest` to attach the nonce.
    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonceString()
        currentAppleNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    func handleAppleCompletion(
        _ result: Result<ASAuthorization, Error>
    ) async throws -> User {
        let authorization = try result.get()
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            throw AuthError.appleCredentialMissing
        }
        guard let tokenData = credential.identityToken else {
            throw AuthError.appleIdentityTokenMissing
        }
        guard let idToken = String(data: tokenData, encoding: .utf8) else {
            throw AuthError.appleIdentityTokenDecodeFailed
        }
        guard let nonce = currentAppleNonce else {
            throw AuthError.appleNonceUnavailable
        }

        let firebaseCredential = OAuthProvider.appleCredential(
            withIDToken: idToken,
            rawNonce: nonce,
            fullName: credential.fullName
        )
        let authResult = try await Auth.auth().signIn(with: firebaseCredential)
        if let fullName = credential.fullName,
           let given = fullName.givenName,
           authResult.user.displayName == nil {
            let displayName = [fullName.givenName, fullName.familyName]
                .compactMap { $0 }
                .joined(separator: " ")
            if !displayName.isEmpty {
                let change = authResult.user.createProfileChangeRequest()
                change.displayName = displayName
                try? await change.commitChanges()
            }
            _ = given  // silence warning when displayName is empty
        }
        currentAppleNonce = nil
        return authResult.user
    }

    // MARK: - Sign out

    func signOut() throws {
        try Auth.auth().signOut()
    }

    // MARK: - Nonce helpers

    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            precondition(status == errSecSuccess, "Failed to generate secure random bytes")
            randoms.forEach { byte in
                if remaining == 0 { return }
                if byte < charset.count {
                    result.append(charset[Int(byte) % charset.count])
                    remaining -= 1
                }
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.map { String(format: "%02x", $0) }.joined()
    }
}

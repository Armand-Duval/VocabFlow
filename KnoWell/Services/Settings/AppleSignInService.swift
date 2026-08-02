import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

enum AppleSignInError: LocalizedError {
    case cancelled
    case missingCredential
    case missingIdentityToken

    var errorDescription: String? {
        switch self {
        case .cancelled:
            L10n.accountAppleCancelled
        case .missingCredential:
            L10n.accountAppleMissingCredential
        case .missingIdentityToken:
            L10n.accountAppleMissingToken
        }
    }
}

@MainActor
final class AppleSignInService: NSObject {
    private var continuation: CheckedContinuation<AccountProfile, Error>?
    private var currentNonce: String?

    func signIn() async throws -> AccountProfile {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let nonce = Self.randomNonceString()
            currentNonce = nonce
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = Self.sha256(nonce)

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    private static func randomNonceString(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        result.reserveCapacity(length)
        for _ in 0..<length {
            result.append(charset.randomElement() ?? "x")
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

extension AppleSignInService: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            continuation?.resume(throwing: AppleSignInError.missingCredential)
            continuation = nil
            return
        }

        let formatter = PersonNameComponentsFormatter()
        let formattedName = credential.fullName.flatMap { name in
            let value = formatter.string(from: name).trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }

        let profile = AccountProfile(
            provider: .apple,
            userID: credential.user,
            displayName: formattedName,
            email: credential.email,
            avatarURL: nil,
            signedInAt: .now
        )
        continuation?.resume(returning: profile)
        continuation = nil
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        if let authError = error as? ASAuthorizationError, authError.code == .canceled {
            continuation?.resume(throwing: AppleSignInError.cancelled)
        } else {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }
}

extension AppleSignInService: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = scene.windows.first(where: \.isKeyWindow) else {
            return ASPresentationAnchor()
        }
        return window
    }
}

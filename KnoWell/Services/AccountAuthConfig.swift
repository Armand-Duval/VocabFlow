import Foundation

enum AccountAuthConfig {
    private static let appIDKey = "WECHAT_APP_ID"
    private static let universalLinkKey = "WECHAT_UNIVERSAL_LINK"
    private static let backendURLKey = "AUTH_BACKEND_URL"

    static var wechatAppID: String? {
        (Bundle.main.object(forInfoDictionaryKey: appIDKey) as? String)
            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    static var wechatUniversalLink: String? {
        (Bundle.main.object(forInfoDictionaryKey: universalLinkKey) as? String)
            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    static var authBackendURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: backendURLKey) as? String else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    static var isWeChatConfigured: Bool {
        wechatAppID != nil && wechatUniversalLink != nil
    }

    /// Controlled by Info.plist `APPLE_SIGN_IN_ENABLED` and Sign in with Apple entitlement.
    static var isAppleSignInAvailable: Bool {
        Bundle.main.object(forInfoDictionaryKey: "APPLE_SIGN_IN_ENABLED") as? Bool ?? false
    }
}

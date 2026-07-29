import Foundation

struct AccountProfile: Codable, Equatable, Sendable {
    enum Provider: String, Codable, Sendable {
        case apple
        case wechat
    }

    let provider: Provider
    let userID: String
    var displayName: String?
    var email: String?
    var avatarURL: String?
    let signedInAt: Date

    var providerLabel: String {
        switch provider {
        case .apple: L10n.accountProviderApple
        case .wechat: L10n.accountProviderWeChat
        }
    }

    var headline: String {
        if let displayName, !displayName.isEmpty {
            return displayName
        }
        if let email, !email.isEmpty {
            return email
        }
        return providerLabel
    }
}

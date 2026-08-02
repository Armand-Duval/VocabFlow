import Foundation
import Observation
import Security

enum AccountStoreError: LocalizedError {
    case keychainError(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .keychainError(let status):
            L10n.accountKeychainError(status)
        case .invalidData:
            L10n.accountInvalidData
        }
    }
}

@Observable
@MainActor
final class AccountSession {
    static let shared = AccountSession()

    private(set) var profile: AccountProfile?
    private let storageKey = "com.knowell.account.profile"

    var isSignedIn: Bool { profile != nil }

    private init() {
        profile = try? AccountKeychain.load(AccountProfile.self, for: storageKey)
    }

    func update(_ profile: AccountProfile) throws {
        try AccountKeychain.save(profile, for: storageKey)
        self.profile = profile
    }

    func signOut() {
        AccountKeychain.delete(storageKey)
        profile = nil
    }
}

enum AccountKeychain {
    private static let service = "com.knowell.app1.account"

    static func save<T: Encodable>(_ value: T, for key: String) throws {
        let data = try JSONEncoder().encode(value)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AccountStoreError.keychainError(status)
        }
    }

    static func load<T: Decodable>(_ type: T.Type, for key: String) throws -> T {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            if status == errSecItemNotFound { throw AccountStoreError.invalidData }
            throw AccountStoreError.keychainError(status)
        }
        guard let data = item as? Data else {
            throw AccountStoreError.invalidData
        }
        return try JSONDecoder().decode(type, from: data)
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

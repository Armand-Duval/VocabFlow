import Foundation

enum APISettings {
    private static let apiKeyKey = "kimi_api_key"
    private static let modelKey = "kimi_model"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: ShareImportStore.appGroupID) ?? .standard
    }

    /// 用户在设置里填写的 Key（可为空）
    static var kimiAPIKey: String {
        get { defaults.string(forKey: apiKeyKey) ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: apiKeyKey) }
    }

    static var kimiModel: String {
        get { defaults.string(forKey: modelKey) ?? "moonshot-v1-8k" }
        set { defaults.set(newValue, forKey: modelKey) }
    }

    /// 用户是否自己配置了 Key
    static var hasUserAPIKey: Bool {
        !kimiAPIKey.isEmpty
    }

    /// 实际用于请求的 Key：优先用户 Key，否则用内置默认
    static var effectiveAPIKey: String {
        if hasUserAPIKey { return kimiAPIKey }
        return DefaultAPIKey.kimi.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var hasDefaultAPIKey: Bool {
        !DefaultAPIKey.kimi.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static var canUseKimi: Bool {
        !effectiveAPIKey.isEmpty
    }

    static var isUsingDefaultKey: Bool {
        !hasUserAPIKey && hasDefaultAPIKey
    }

    static var keySourceDescription: String {
        if hasUserAPIKey { return L10n.keySourceUser }
        if hasDefaultAPIKey { return L10n.keySourceDefault }
        return L10n.keySourceMissing
    }

    static let baseURL = "https://api.moonshot.cn/v1"

    static let availableModels = [
        "moonshot-v1-8k",
        "moonshot-v1-32k",
        "kimi-k2.5",
        "kimi-k2.6"
    ]

    static func migrateToAppGroupIfNeeded() {
        let legacy = UserDefaults.standard
        guard legacy !== defaults else { return }

        if defaults.string(forKey: apiKeyKey) == nil,
           let key = legacy.string(forKey: apiKeyKey), !key.isEmpty {
            defaults.set(key, forKey: apiKeyKey)
        }

        if defaults.string(forKey: modelKey) == nil,
           let model = legacy.string(forKey: modelKey), !model.isEmpty {
            defaults.set(model, forKey: modelKey)
        }
    }
}

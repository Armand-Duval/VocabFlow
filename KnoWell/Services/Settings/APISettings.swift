import Foundation

enum KnoWellCloud {
    static let origin = "https://api.knowellcards.com"
    static let baseURL = origin + "/v1"
    static let healthURL = origin + "/health"
    static let appToken = "3b9dbb99ba2999efc87fdaebead29ca8ce5203a1c5304a9c"
    static var isEnabled: Bool { !appToken.isEmpty }
}

enum APISettings {
    private static let apiKeyKey = "kimi_api_key"
    private static let modelKey = "kimi_model"
    private static let providerKey = "ai_provider"
    private static let customBaseURLKey = "ai_custom_base_url"
    private static let customModelKey = "ai_custom_model"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: ShareImportStore.appGroupID) ?? .standard
    }

    static var provider: AIProvider {
        get {
            guard let raw = defaults.string(forKey: providerKey),
                  let value = AIProvider(rawValue: raw) else {
                return .deepseek
            }
            return value
        }
        set {
            defaults.set(newValue.rawValue, forKey: providerKey)
            if !newValue.suggestedModels.contains(kimiModel),
               !newValue.suggestedModels.isEmpty,
               customModelID.isEmpty {
                kimiModel = newValue.defaultModel
            }
        }
    }

    /// User-entered API key (may be empty).
    static var kimiAPIKey: String {
        get { defaults.string(forKey: apiKeyKey) ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: apiKeyKey) }
    }

    static var kimiModel: String {
        get {
            let stored = defaults.string(forKey: modelKey) ?? ""
            if !stored.isEmpty { return stored }
            return provider.defaultModel
        }
        set { defaults.set(newValue, forKey: modelKey) }
    }

    /// Effective model ID (picker selection or custom model override).
    /// Default-key fallback uses a model that matches the effective provider.
    static var effectiveModel: String {
        if isUsingDefaultKey {
            let fallbackProvider = effectiveProvider
            if fallbackProvider.suggestedModels.contains(kimiModel) {
                return kimiModel
            }
            return fallbackProvider.defaultModel
        }
        let custom = customModelID
        if !custom.isEmpty { return custom }
        return kimiModel
    }

    /// Moonshot Kimi K2.5 / K2.6 only accept `temperature: 1`.
    static func chatTemperature(preferred: Double) -> Double {
        let model = effectiveModel.lowercased()
        if model.contains("kimi-k2") || model.contains("kimi/k2") {
            return 1
        }
        return preferred
    }

    static var customModelID: String {
        get { defaults.string(forKey: customModelKey) ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: customModelKey) }
    }

    static var customBaseURL: String {
        get { defaults.string(forKey: customBaseURLKey) ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: customBaseURLKey) }
    }

    static var hasUserAPIKey: Bool {
        !kimiAPIKey.isEmpty
    }

    /// Bundled default key for a provider (empty if unsupported / not configured).
    static func defaultAPIKey(for provider: AIProvider) -> String {
        switch provider {
        case .moonshot:
            DefaultAPIKey.kimi.trimmingCharacters(in: .whitespacesAndNewlines)
        case .deepseek:
            DefaultAPIKey.deepseek.trimmingCharacters(in: .whitespacesAndNewlines)
        default:
            ""
        }
    }

    /// Any bundled default key exists (DeepSeek and/or Moonshot).
    static var hasDefaultAPIKey: Bool {
        !defaultAPIKey(for: .deepseek).isEmpty || !defaultAPIKey(for: .moonshot).isEmpty
    }

    /// Empty user key → official proxy, else a bundled default key.
    static var isUsingDefaultKey: Bool {
        !hasUserAPIKey && !usesCloudProxy && !defaultAPIKey(for: effectiveProvider).isEmpty
    }

    /// No personal key → talk to KnoWell's proxy (upstream key stays on the server).
    static var usesCloudProxy: Bool {
        !hasUserAPIKey && KnoWellCloud.isEnabled
    }

    static var deviceID: String {
        let key = "knowell_device_id"
        if let existing = defaults.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let id = UUID().uuidString
        defaults.set(id, forKey: key)
        return id
    }

    /// Prefer user key; otherwise the cloud token, then bundled DeepSeek / Moonshot.
    static var effectiveAPIKey: String {
        if hasUserAPIKey { return kimiAPIKey }
        if usesCloudProxy { return KnoWellCloud.appToken }
        let forProvider = defaultAPIKey(for: provider)
        if !forProvider.isEmpty { return forProvider }
        if !defaultAPIKey(for: .deepseek).isEmpty { return defaultAPIKey(for: .deepseek) }
        return defaultAPIKey(for: .moonshot)
    }

    /// Requests use the selected provider when the user supplied a key, or when that
    /// provider has a bundled default. Cloud proxy keeps the user's picker but
    /// sends traffic to KnoWellCloud.
    static var effectiveProvider: AIProvider {
        if hasUserAPIKey { return provider }
        if usesCloudProxy { return provider }
        if !defaultAPIKey(for: provider).isEmpty { return provider }
        if !defaultAPIKey(for: .deepseek).isEmpty { return .deepseek }
        if !defaultAPIKey(for: .moonshot).isEmpty { return .moonshot }
        return provider
    }

    static var canUseKimi: Bool { canUseAI }

    static var canUseAI: Bool {
        if usesCloudProxy { return true }
        return !effectiveAPIKey.isEmpty && !baseURL.isEmpty && !effectiveModel.isEmpty
    }

    static var keySourceDescription: String {
        if hasUserAPIKey { return L10n.keySourceUser }
        if usesCloudProxy { return L10n.keySourceCloud }
        if isUsingDefaultKey { return L10n.keySourceDefault }
        return L10n.keySourceMissing
    }

    static var baseURL: String {
        if usesCloudProxy {
            return KnoWellCloud.baseURL
        }
        switch effectiveProvider {
        case .custom:
            return normalizedBaseURL(customBaseURL)
        default:
            return effectiveProvider.defaultBaseURL
        }
    }

    static func applyChatHeaders(to request: inout URLRequest) {
        if usesCloudProxy {
            request.setValue(KnoWellCloud.appToken, forHTTPHeaderField: "X-KnoWell-Token")
            request.setValue(deviceID, forHTTPHeaderField: "X-Device-Id")
            return
        }
        request.setValue("Bearer \(effectiveAPIKey)", forHTTPHeaderField: "Authorization")
        if effectiveProvider == .openrouter {
            request.setValue("https://knowell.app", forHTTPHeaderField: "HTTP-Referer")
            request.setValue("KnoWell", forHTTPHeaderField: "X-Title")
        }
    }

    static var chatCompletionsURL: String {
        baseURL + "/chat/completions"
    }

    static var modelsURL: String {
        baseURL + "/models"
    }

    static var availableModels: [String] {
        provider.suggestedModels
    }

    static func modelDescription(for model: String) -> String {
        provider.modelDescription(for: model)
    }

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

        if defaults.string(forKey: providerKey) == nil,
           let provider = legacy.string(forKey: providerKey), !provider.isEmpty {
            defaults.set(provider, forKey: providerKey)
        }
    }

    private static func normalizedBaseURL(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") {
            value.removeLast()
        }
        // Accept either `https://host/v1` or `https://host/v1/chat/completions`
        if value.hasSuffix("/chat/completions") {
            value = String(value.dropLast("/chat/completions".count))
        }
        return value
    }
}

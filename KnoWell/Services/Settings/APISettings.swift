import Foundation

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
                return .moonshot
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
    /// Default-key fallback always uses a Moonshot model.
    static var effectiveModel: String {
        if isUsingDefaultKey {
            if AIProvider.moonshot.suggestedModels.contains(kimiModel) {
                return kimiModel
            }
            return AIProvider.moonshot.defaultModel
        }
        let custom = customModelID
        if !custom.isEmpty { return custom }
        return kimiModel
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

    /// Bundled default key exists (not tied to the provider picker).
    static var hasDefaultAPIKey: Bool {
        !DefaultAPIKey.kimi.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Empty user key → use bundled default AI (Moonshot key + endpoint).
    static var isUsingDefaultKey: Bool {
        !hasUserAPIKey && hasDefaultAPIKey
    }

    /// Prefer user key; if empty, fall back to bundled default key regardless of picker.
    static var effectiveAPIKey: String {
        if hasUserAPIKey { return kimiAPIKey }
        return DefaultAPIKey.kimi.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Requests use the selected provider only when the user supplied a key.
    /// Otherwise route to default AI (Moonshot) so the default key matches the endpoint.
    static var effectiveProvider: AIProvider {
        if hasUserAPIKey { return provider }
        if hasDefaultAPIKey { return .moonshot }
        return provider
    }

    static var canUseKimi: Bool { canUseAI }

    static var canUseAI: Bool {
        !effectiveAPIKey.isEmpty && !baseURL.isEmpty && !effectiveModel.isEmpty
    }

    static var keySourceDescription: String {
        if hasUserAPIKey { return L10n.keySourceUser }
        if hasDefaultAPIKey { return L10n.keySourceDefault }
        return L10n.keySourceMissing
    }

    static var baseURL: String {
        switch effectiveProvider {
        case .custom:
            return normalizedBaseURL(customBaseURL)
        default:
            return effectiveProvider.defaultBaseURL
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

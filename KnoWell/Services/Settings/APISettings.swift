import Foundation
import Observation

enum KnoWellCloud {
    static let origin = "https://api.knowellcards.com"
    static let baseURL = origin + "/v1"
    static let healthURL = origin + "/health"
    static let quotaURL = origin + "/v1/quota"
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
    static var effectiveModel: String {
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

    /// Prefer user key; otherwise the cloud token.
    static var effectiveAPIKey: String {
        if hasUserAPIKey { return kimiAPIKey }
        if usesCloudProxy { return KnoWellCloud.appToken }
        return ""
    }

    static var effectiveProvider: AIProvider {
        provider
    }

    static var canUseAI: Bool {
        if usesCloudProxy { return true }
        return !effectiveAPIKey.isEmpty && !baseURL.isEmpty && !effectiveModel.isEmpty
    }

    static var keySourceDescription: String {
        if hasUserAPIKey { return L10n.keySourceUser }
        if usesCloudProxy { return L10n.keySourceCloud }
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

enum CloudAIQuota {
    struct Snapshot: Equatable {
        var date: String
        var used: Int
        var limit: Int
        var remaining: Int

        var isExhausted: Bool { remaining <= 0 }

        func blocks(needed: Int) -> Bool {
            remaining < max(needed, 1)
        }
    }

    @MainActor
    static func insufficientError(needed: Int) -> CardGeneratorError? {
        guard APISettings.usesCloudProxy else { return nil }
        guard let snapshot = CloudAIQuotaStore.shared.snapshot else { return nil }
        let units = max(needed, 1)
        guard snapshot.blocks(needed: units) else { return nil }
        return .quotaInsufficient(needed: units, remaining: snapshot.remaining)
    }

    static func isExhausted(_ error: Error) -> Bool {
        looksLike(error.localizedDescription)
    }

    static func looksLike(_ message: String) -> Bool {
        if message == L10n.aiDailyQuotaReached { return true }
        let lower = message.lowercased()
        return message.contains("今日免费")
            || message.contains("次数已用完")
            || message.contains("额度不足")
            || message.contains("额度已用完")
            || lower.contains("daily quota")
            || lower.contains("free ai generations are used up")
            || lower.contains("free ai quota")
    }

    static func mappedMessage(statusCode: Int, raw: String) -> String? {
        if statusCode == 429 || looksLike(raw) {
            return L10n.aiDailyQuotaReached
        }
        return nil
    }

    static func ingest(http: HTTPURLResponse, data: Data? = nil) {
        guard APISettings.usesCloudProxy else { return }
        guard let snapshot = parse(http: http, data: data) else { return }
        Task { @MainActor in
            CloudAIQuotaStore.shared.apply(snapshot, authoritative: false)
        }
    }

    static func parse(http: HTTPURLResponse, data: Data?) -> Snapshot? {
        let headerUsed = intHeader(http, names: ["X-KnoWell-Used", "X-Knowell-Used"])
        let headerLimit = intHeader(http, names: ["X-KnoWell-Limit", "X-Knowell-Limit"])
        let headerRemaining = intHeader(http, names: ["X-KnoWell-Remaining", "X-Knowell-Remaining"])

        var body: [String: Any] = [:]
        if let data,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            body = json
        }

        let used = headerUsed ?? intValue(body["used"])
        let limit = headerLimit ?? intValue(body["limit"])
        let remaining = headerRemaining ?? intValue(body["remaining"])
        guard let used, let limit, let remaining, limit > 0 else { return nil }

        let date = (body["date"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ISO8601DateFormatter().string(from: Date()).prefix(10).description
        return Snapshot(date: date, used: used, limit: limit, remaining: remaining)
    }

    private static func intHeader(_ http: HTTPURLResponse, names: [String]) -> Int? {
        for name in names {
            if let raw = http.value(forHTTPHeaderField: name),
               let value = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return value
            }
        }
        return nil
    }

    private static func intValue(_ raw: Any?) -> Int? {
        if let value = raw as? Int { return value }
        if let value = raw as? Double { return Int(value) }
        if let value = raw as? String { return Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }
}

@Observable
@MainActor
final class CloudAIQuotaStore {
    static let shared = CloudAIQuotaStore()

    private(set) var snapshot: CloudAIQuota.Snapshot?
    private var lastRefresh: Date?

    func apply(_ snapshot: CloudAIQuota.Snapshot, authoritative: Bool = true) {
        if !authoritative, let current = self.snapshot, current.date == snapshot.date {
            // Parallel chat responses can finish out of order. Keep the most consumed count
            // so remaining never jumps back up mid-job.
            if snapshot.used < current.used { return }
            if snapshot.used == current.used, snapshot.remaining > current.remaining { return }
        }
        self.snapshot = snapshot
        lastRefresh = .now
    }

    func refresh(force: Bool = false) async {
        guard APISettings.usesCloudProxy else {
            snapshot = nil
            return
        }
        if !force, let lastRefresh, Date.now.timeIntervalSince(lastRefresh) < 8 {
            return
        }
        guard let url = URL(string: KnoWellCloud.quotaURL) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        APISettings.applyChatHeaders(to: &request)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }
            if let snapshot = CloudAIQuota.parse(http: http, data: data) {
                apply(snapshot, authoritative: true)
            }
        } catch {
            // Keep the last known count; generate still fails closed on 429.
        }
    }
}

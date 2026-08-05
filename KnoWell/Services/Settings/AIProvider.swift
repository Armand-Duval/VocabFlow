import Foundation

/// OpenAI-compatible chat providers used for card generation.
enum AIProvider: String, CaseIterable, Identifiable, Codable {
    case deepseek
    case moonshot
    case openai
    case openrouter
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .moonshot: L10n.aiProviderMoonshot
        case .openai: L10n.aiProviderOpenAI
        case .deepseek: L10n.aiProviderDeepSeek
        case .openrouter: L10n.aiProviderOpenRouter
        case .custom: L10n.aiProviderCustom
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .moonshot: "https://api.moonshot.cn/v1"
        case .openai: "https://api.openai.com/v1"
        case .deepseek: "https://api.deepseek.com/v1"
        case .openrouter: "https://openrouter.ai/api/v1"
        case .custom: ""
        }
    }

    var suggestedModels: [String] {
        switch self {
        case .moonshot:
            ["moonshot-v1-8k", "moonshot-v1-32k", "kimi-k2.5", "kimi-k2.6"]
        case .openai:
            ["gpt-4o-mini", "gpt-4o", "gpt-4.1-mini", "gpt-4.1"]
        case .deepseek:
            ["deepseek-chat", "deepseek-reasoner"]
        case .openrouter:
            [
                "openai/gpt-4o-mini",
                "anthropic/claude-3.5-sonnet",
                "google/gemini-2.0-flash-001",
                "deepseek/deepseek-chat"
            ]
        case .custom:
            []
        }
    }

    var defaultModel: String {
        suggestedModels.first ?? ""
    }

    var supportsCustomBaseURL: Bool {
        self == .custom
    }

    var apiKeyPlaceholder: String {
        switch self {
        case .moonshot: L10n.apiKeyPlaceholder
        case .openai: L10n.aiProviderOpenAIKeyPlaceholder
        case .deepseek: L10n.aiProviderDeepSeekKeyPlaceholder
        case .openrouter: L10n.aiProviderOpenRouterKeyPlaceholder
        case .custom: L10n.aiProviderCustomKeyPlaceholder
        }
    }

    func modelDescription(for model: String) -> String {
        switch (self, model) {
        case (.moonshot, "moonshot-v1-8k"): L10n.settingsModel8kDetail
        case (.moonshot, "moonshot-v1-32k"): L10n.settingsModel32kDetail
        case (.moonshot, "kimi-k2.5"): L10n.settingsModelK2Detail
        case (.moonshot, "kimi-k2.6"): L10n.settingsModelK26Detail
        case (.openai, "gpt-4o-mini"): L10n.aiModelOpenAI4oMiniDetail
        case (.openai, "gpt-4o"): L10n.aiModelOpenAI4oDetail
        case (.deepseek, "deepseek-chat"): L10n.aiModelDeepSeekChatDetail
        case (.deepseek, "deepseek-reasoner"): L10n.aiModelDeepSeekReasonerDetail
        case (.openrouter, _): L10n.aiModelOpenRouterDetail
        case (.custom, _): L10n.aiModelCustomDetail
        default: L10n.settingsModelDefaultDetail
        }
    }
}

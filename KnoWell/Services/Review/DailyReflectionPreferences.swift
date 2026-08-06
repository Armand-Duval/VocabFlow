import Foundation

enum DailyReflectionPreset: String, CaseIterable, Identifiable {
    case philosophy = "哲理"
    case romantic = "浪漫"
    case englishPoetry = "英文诗"
    case classical = "文言"
    case wisdom = "智慧"

    var id: String { rawValue }
}

enum DailyReflectionPreferences {
    static let maxKeywords = 3
    static let maxKeywordLength = 8
    private static let keywordsKey = "dailyReflection.keywords.v1"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: ShareImportStore.appGroupID) ?? .standard
    }

    static var keywords: [String] {
        get {
            guard let stored = defaults.stringArray(forKey: keywordsKey) else { return [] }
            return stored.compactMap(sanitize).prefix(maxKeywords).map { String($0) }
        }
        set {
            let cleaned = Array(newValue.compactMap(sanitize).prefix(maxKeywords))
            if cleaned.isEmpty {
                defaults.removeObject(forKey: keywordsKey)
            } else {
                defaults.set(cleaned, forKey: keywordsKey)
            }
        }
    }

    static var hasKeywords: Bool { !keywords.isEmpty }

    static func sanitize(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let forbidden = ["/", "|", "\\", "\n", "\r", "```", "**", "__", "<", ">"]
        for symbol in forbidden {
            text = text.replacingOccurrences(of: symbol, with: "")
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.count > maxKeywordLength {
            text = String(text.prefix(maxKeywordLength))
        }
        return text
    }

    static var promptSnippet: String? {
        let items = keywords
        guard !items.isEmpty else { return nil }
        return items.joined(separator: "、")
    }

    static func toggleKeyword(_ raw: String) {
        guard let word = sanitize(raw) else { return }
        var current = keywords
        if let index = current.firstIndex(of: word) {
            current.remove(at: index)
        } else if current.count < maxKeywords {
            current.append(word)
        }
        keywords = current
    }

    static func addKeyword(_ raw: String) -> Bool {
        guard let word = sanitize(raw) else { return false }
        var current = keywords
        guard !current.contains(word) else { return false }
        guard current.count < maxKeywords else { return false }
        current.append(word)
        keywords = current
        return true
    }

    static func removeKeyword(_ word: String) {
        keywords = keywords.filter { $0 != word }
    }

    static func clear() {
        keywords = []
    }
}

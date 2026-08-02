import Foundation

/// App Group index of existing deck + word + sentence keys for Share / extension pre-checks.
/// Save-time dedupe in the main app remains the source of truth.
enum SharedDedupeIndex {
    private static let fileName = "card-dedupe-index.json"
    private static let separator = "\u{1f}"

    static func normalizedWord(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func normalizedSentence(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
    }

    static func key(deckID: UUID, word: String, sentence: String) -> String? {
        let wordKey = normalizedWord(word)
        let sentenceKey = normalizedSentence(sentence)
        guard !wordKey.isEmpty, !sentenceKey.isEmpty else { return nil }
        return [deckID.uuidString, wordKey, sentenceKey].joined(separator: separator)
    }

    static func contains(deckID: UUID, word: String, sentence: String) -> Bool {
        guard let key = key(deckID: deckID, word: word, sentence: sentence) else { return false }
        return loadKeys().contains(key)
    }

    /// Keeps words that are not already in the deck for this sentence.
    static func filterNewWords(
        _ words: [String],
        deckID: UUID,
        sentence: String
    ) -> (kept: [String], skippedCount: Int) {
        var kept: [String] = []
        var skipped = 0
        var seen = Set<String>()

        for word in words {
            let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let dedupeKey = normalizedWord(trimmed)
            guard !seen.contains(dedupeKey) else {
                skipped += 1
                continue
            }
            seen.insert(dedupeKey)

            if contains(deckID: deckID, word: trimmed, sentence: sentence) {
                skipped += 1
            } else {
                kept.append(trimmed)
            }
        }
        return (kept, skipped)
    }

    /// Dedupe against each unit's own sentence (must match keys written at save time).
    static func filterNewUnits(
        _ units: [OCRImportUnit],
        deckID: UUID
    ) -> (units: [OCRImportUnit], skippedCount: Int) {
        var result: [OCRImportUnit] = []
        var skipped = 0
        var seenKeys = Set<String>()

        for unit in units {
            let sentence = unit.sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sentence.isEmpty else { continue }

            var keptWords: [String] = []
            for word in unit.words {
                let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                guard let key = key(deckID: deckID, word: trimmed, sentence: sentence) else { continue }
                guard !seenKeys.contains(key) else {
                    skipped += 1
                    continue
                }
                seenKeys.insert(key)

                if contains(deckID: deckID, word: trimmed, sentence: sentence) {
                    skipped += 1
                } else {
                    keptWords.append(trimmed)
                }
            }
            if !keptWords.isEmpty {
                result.append(OCRImportUnit(sentence: sentence, words: keptWords))
            }
        }
        return (result, skipped)
    }

    static func replaceAll(keys: Set<String>) {
        saveKeys(keys)
    }

    static func insert(deckID: UUID, word: String, sentence: String) {
        guard let key = key(deckID: deckID, word: word, sentence: sentence) else { return }
        var keys = loadKeys()
        guard keys.insert(key).inserted else { return }
        saveKeys(keys)
    }

    static func insert(deckID: UUID, pairs: [(word: String, sentence: String)]) {
        var keys = loadKeys()
        var changed = false
        for pair in pairs {
            guard let key = key(deckID: deckID, word: pair.word, sentence: pair.sentence) else { continue }
            if keys.insert(key).inserted {
                changed = true
            }
        }
        if changed {
            saveKeys(keys)
        }
    }

    // MARK: - Persistence

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: ShareImportStore.appGroupID)?
            .appendingPathComponent(fileName)
    }

    private static func loadKeys() -> Set<String> {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(list)
    }

    private static func saveKeys(_ keys: Set<String>) {
        guard let url = fileURL,
              let data = try? JSONEncoder().encode(Array(keys).sorted()) else {
            return
        }
        try? data.write(to: url, options: .atomic)
    }
}

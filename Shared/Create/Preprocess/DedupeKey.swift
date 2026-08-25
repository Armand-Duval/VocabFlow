import Foundation

/// Deck + word + sentence identity used by save-time and Share pre-checks.
public enum DedupeKey {
    private static let separator = "\u{1f}"

    public static func normalizedWord(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public static func normalizedSentence(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
    }

    public static func key(deckID: UUID, word: String, sentence: String) -> String? {
        let wordKey = normalizedWord(word)
        let sentenceKey = normalizedSentence(sentence)
        guard !wordKey.isEmpty, !sentenceKey.isEmpty else { return nil }
        return [deckID.uuidString, wordKey, sentenceKey].joined(separator: separator)
    }
}

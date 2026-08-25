import Foundation

public enum VocabularyWordAddResult: Equatable, Sendable {
    case added(String)
    case duplicate(String)
    case existsInDeck(String)
    case empty
}

public enum VocabularyWords {
    public static func parse(from text: String) -> [String] {
        text
            .split(separator: ",")
            .map { normalized(String($0)) }
            .filter { !$0.isEmpty }
    }

    public static func join(_ words: [String]) -> String {
        words.joined(separator: ", ")
    }

    /// Live Text / OCR selections often include the following comma or period.
    public static func normalized(_ word: String) -> String {
        word
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: wrappingMarks)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func append(_ word: String, to words: inout [String]) -> VocabularyWordAddResult {
        let trimmed = normalized(word)
        guard !trimmed.isEmpty else { return .empty }
        if words.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return .duplicate(trimmed)
        }
        words.append(trimmed)
        return .added(trimmed)
    }

    /// Sentence punctuation that sticks to a Live Text token; keep internal marks like apostrophes.
    private static let wrappingMarks = CharacterSet(charactersIn: ",.;:!?，。、；：！？…·•\"“”()[]{}「」『』《》<>")
}

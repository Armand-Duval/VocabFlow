import Foundation

struct ParsedImportText: Equatable {
    let sentence: String
    let prefilledWords: [String]
}

enum ImportTextAnalyzer {
    static func parse(_ text: String) -> ParsedImportText {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ParsedImportText(sentence: "", prefilledWords: [])
        }

        if isLikelySingleVocabularyItem(trimmed) {
            return ParsedImportText(sentence: "", prefilledWords: [trimmed])
        }

        return ParsedImportText(sentence: trimmed, prefilledWords: [])
    }

    static func isLikelySingleVocabularyItem(_ text: String) -> Bool {
        guard !text.contains("\n") else { return false }

        let sentenceEnders = CharacterSet(charactersIn: ".!?。！？")
        if text.unicodeScalars.contains(where: { sentenceEnders.contains($0) }) {
            return false
        }

        let parts = text.split(whereSeparator: \.isWhitespace)
        return parts.count <= 2 && text.count <= 40
    }
}

import Foundation

/// One importable context: a sentence plus the highlighted words inside it.
struct OCRImportUnit: Equatable, Sendable {
    var sentence: String
    var words: [String]
}

/// Unified OCR output for create / share flows (ready for Android ML Kit later).
struct OCRResult: Equatable, Sendable {
    var fullText: String
    /// Words / phrases detected under highlighter marks.
    var highlightedWords: [String]
    /// Preferred import payloads: sentence + words (not the whole page).
    var importUnits: [OCRImportUnit]

    static let empty = OCRResult(fullText: "", highlightedWords: [], importUnits: [])

    /// Sentence field for the single-box create UI.
    var preferredImportSentence: String {
        if importUnits.isEmpty {
            return fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return importUnits
            .map(\.sentence)
            .joined(separator: "\n\n")
    }

    var preferredImportWords: [String] {
        if importUnits.isEmpty { return highlightedWords }
        var seen = Set<String>()
        var ordered: [String] = []
        for word in importUnits.flatMap(\.words) {
            let key = word.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            ordered.append(word)
        }
        return ordered
    }

    var hasHighlightContext: Bool {
        !importUnits.isEmpty
    }
}

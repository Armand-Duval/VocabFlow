import Foundation

public enum OCRImportKind: Equatable, Sendable {
    case none
    case highlight
    case vocabPage
}

/// Unified OCR / import proposal for create and share flows.
public struct OCRResult: Equatable, Sendable {
    public var fullText: String
    /// Words / phrases detected under highlighter marks.
    public var highlightedWords: [String]
    /// Preferred import payloads: sentence + words (not the whole page).
    public var importUnits: [OCRImportUnit]
    /// App Group relative path for the source image used for OCR, if saved.
    public var sourceImagePath: String?
    /// How `importUnits` were produced. Share/create use units whenever they are non-empty.
    public var importKind: OCRImportKind

    public init(
        fullText: String,
        highlightedWords: [String],
        importUnits: [OCRImportUnit],
        sourceImagePath: String? = nil,
        importKind: OCRImportKind = .none
    ) {
        self.fullText = fullText
        self.highlightedWords = highlightedWords
        self.importUnits = importUnits
        self.sourceImagePath = sourceImagePath
        self.importKind = importKind
    }

    public static let empty = OCRResult(
        fullText: "",
        highlightedWords: [],
        importUnits: [],
        sourceImagePath: nil,
        importKind: .none
    )

    /// Sentence field for the single-box create UI.
    /// Highlight imports: one block per marked sentence (not the whole page).
    public var preferredImportSentence: String {
        if importUnits.isEmpty {
            return fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return OCRContextExtractor.joinedImportSentences(importUnits)
            ?? fullText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var preferredImportWords: [String] {
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

    public var hasHighlightContext: Bool {
        !importUnits.isEmpty
    }

    /// Drop false highlighter hits (App chrome / truncated body) so share-OCR keeps page prose.
    public func sanitizedForImport() -> OCRResult {
        let cleanedFullText = OCRChromeFilter.strippingChromeLines(from: fullText)
        let cleanedWords = highlightedWords.filter { word in
            !OCRChromeFilter.isChromePhrase(word)
                && OCRChromeFilter.isPlausibleVocabularyToken(word, in: cleanedFullText)
        }
        let cleanedUnits = importUnits.compactMap { unit -> OCRImportUnit? in
            let words = unit.words.filter { word in
                !OCRChromeFilter.isChromePhrase(word)
                    && OCRChromeFilter.isPlausibleVocabularyToken(word, in: cleanedFullText)
            }
            guard !words.isEmpty else { return nil }
            return OCRImportUnit(sentence: unit.sentence, words: words)
        }

        let result = OCRResult(
            fullText: cleanedFullText,
            highlightedWords: cleanedWords,
            importUnits: cleanedUnits,
            sourceImagePath: sourceImagePath,
            importKind: importKind
        )

        if result.shouldDiscardHighlightContext {
            return OCRResult(
                fullText: cleanedFullText,
                highlightedWords: [],
                importUnits: [],
                sourceImagePath: sourceImagePath,
                importKind: .none
            )
        }
        return result
    }

    /// Only drop highlight context when it looks like App / share-sheet chrome —
    /// not when a few real book sentences sit on a longer page (that ratio is normal).
    private var shouldDiscardHighlightContext: Bool {
        guard hasHighlightContext else { return false }
        let unitText = importUnits
            .map(\.sentence)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !unitText.isEmpty else { return false }

        if OCRChromeFilter.looksLikeChromeBlob(unitText) { return true }

        if highlightedWords.allSatisfy(OCRChromeFilter.isChromePhrase) { return true }

        let full = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        if full.count >= 120, unitText.count < 36, unitText.count * 15 < full.count {
            return true
        }
        return false
    }
}

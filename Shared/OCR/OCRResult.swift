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
    /// App Group relative path for the source image used for OCR, if saved.
    var sourceImagePath: String?

    static let empty = OCRResult(fullText: "", highlightedWords: [], importUnits: [], sourceImagePath: nil)

    /// Sentence field for the single-box create UI.
    /// Highlight imports: one block per marked sentence (not the whole page).
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

    /// Drop false highlighter hits (App chrome / truncated body) so share-OCR keeps page prose.
    func sanitizedForImport() -> OCRResult {
        let cleanedWords = highlightedWords.filter { !OCRChromeFilter.isChromePhrase($0) }
        let cleanedUnits = importUnits.compactMap { unit -> OCRImportUnit? in
            let words = unit.words.filter { !OCRChromeFilter.isChromePhrase($0) }
            guard !words.isEmpty else { return nil }
            return OCRImportUnit(sentence: unit.sentence, words: words)
        }

        var result = OCRResult(
            fullText: fullText,
            highlightedWords: cleanedWords,
            importUnits: cleanedUnits,
            sourceImagePath: sourceImagePath
        )

        if result.shouldDiscardHighlightContext {
            return OCRResult(
                fullText: fullText,
                highlightedWords: [],
                importUnits: [],
                sourceImagePath: sourceImagePath
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

        // Extremely short chrome strip vs long OCR page (e.g. nav labels only).
        let full = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        if full.count >= 120, unitText.count < 36, unitText.count * 15 < full.count {
            return true
        }
        return false
    }
}

/// Filters App / share-sheet chrome that OCR often mistakes for highlighter vocabulary.
enum OCRChromeFilter {
    private static let exactChrome: Set<String> = [
        "review", "library", "create", "cancel", "generate", "generate cards",
        "manage decks", "manage deck", "target deck", "deck", "add word",
        "add", "done", "close", "ok", "settings", "save", "search",
        "shared content ready", "imported from clipboard",
        "复习", "词库", "制卡", "取消", "生成", "生成卡片", "管理词库",
        "目标词库", "添加生词", "完成", "关闭", "设置", "保存", "搜索"
    ]

    static func isChromePhrase(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        if trimmed.count == 1, !trimmed.first!.isLetter { return true }

        let key = trimmed.lowercased()
        if exactChrome.contains(key) { return true }

        // Multi-token chrome glued by softJoin: "Manage Decks Generate cards".
        let tokens = key
            .split(whereSeparator: { $0.isWhitespace || $0 == "|" || $0 == "·" || $0 == "＋" || $0 == "+" })
            .map(String.init)
            .filter { !$0.isEmpty }
        if tokens.count >= 2, tokens.allSatisfy({ exactChrome.contains($0) || exactChrome.contains($0.replacingOccurrences(of: "cards", with: " cards").trimmingCharacters(in: .whitespaces)) }) {
            return true
        }
        let chromeHitCount = tokens.filter { token in
            exactChrome.contains(token)
                || exactChrome.contains(token.replacingOccurrences(of: "cards", with: ""))
                || ["manage", "decks", "cards", "generate"].contains(token)
        }.count
        if tokens.count >= 2, chromeHitCount * 2 >= tokens.count { return true }
        return false
    }

    static func looksLikeChromeBlob(_ text: String) -> Bool {
        let lower = text.lowercased()
        let markers = [
            "manage decks", "generate cards", "review", "library", "create",
            "管理词库", "生成卡片", "复习", "词库", "制卡"
        ]
        let hits = markers.filter { lower.contains($0) }.count
        return hits >= 2
    }
}

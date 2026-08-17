import Foundation

/// One importable context: a sentence plus the highlighted words inside it.
struct OCRImportUnit: Equatable, Sendable {
    var sentence: String
    var words: [String]
}

enum OCRImportKind: Equatable, Sendable {
    case none
    case highlight
    case vocabPage
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
    /// How `importUnits` were produced. Share/create use units whenever they are non-empty.
    var importKind: OCRImportKind = .none

    static let empty = OCRResult(
        fullText: "",
        highlightedWords: [],
        importUnits: [],
        sourceImagePath: nil,
        importKind: .none
    )

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

        // Overlay glow often trips the highlighter mask. If every hit is overlay /
        // App chrome, fall back to the full OCR page — not a per-screenshot word list.
        if highlightedWords.allSatisfy(OCRChromeFilter.isChromePhrase) { return true }

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
        if looksLikeLatinHUDChip(trimmed) { return true }

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

    /// Drop OCR shards ("ing", "ning", "zontal") that are not standalone words on the page.
    static func isPlausibleVocabularyToken(_ raw: String, in fullText: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let hasCJK = trimmed.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value)
        }
        if hasCJK {
            return trimmed.count <= 8
        }

        let letters = trimmed.filter(\.isLetter)
        guard letters.count >= 4 else { return false }

        let escaped = NSRegularExpression.escapedPattern(for: trimmed)
        let pattern = "\\b\(escaped)\\b"
        return fullText.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Overlay control vs body text. Geometry / typography only — screenshots
    /// differ, so never match a list of button captions.
    static func looksLikeOverlayControl(token: String, lineText: String, boxArea: CGFloat) -> Bool {
        if boxArea > 0, boxArea < 0.0012 { return true }
        if looksLikeLatinHUDChip(token) { return true }
        if looksLikeStandaloneChip(token: token, line: lineText) { return true }
        return false
    }

    /// HUD chips: short ALL-CAPS Latin, no CJK, no digits/punctuation.
    /// Length band is the button shape, not any particular word.
    static func looksLikeLatinHUDChip(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let letters = trimmed.filter(\.isLetter)
        guard letters.count >= 3, letters.count <= 8 else { return false }
        if trimmed.unicodeScalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) }) {
            return false
        }
        let nonSpace = trimmed.filter { !$0.isWhitespace && $0 != "-" }
        guard !nonSpace.isEmpty, nonSpace.allSatisfy(\.isLetter) else { return false }
        return letters.allSatisfy { character in
            character.isASCII && character.isUppercase
        }
    }

    /// Vocabulary sits inside a sentence. A control is usually the whole OCR line.
    /// Latin-only: short CJK lines are often real dialogue.
    static func looksLikeStandaloneChip(token: String, line: String) -> Bool {
        let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.count >= 2, line.count <= 12 else { return false }
        if line.unicodeScalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) }) {
            return false
        }
        let sentenceMarks = CharacterSet(charactersIn: ".!?。！？…,;:\"'“”")
        if line.unicodeScalars.contains(where: { sentenceMarks.contains($0) }) { return false }
        if line.contains(where: { $0.isASCII && $0.isLetter && $0.isLowercase }) { return false }
        let compactLine = line.filter { !$0.isWhitespace }
        let compactToken = token.filter { !$0.isWhitespace }
        return compactLine.compare(compactToken, options: .caseInsensitive) == .orderedSame
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

    static func strippingChromeLines(from text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                guard !line.isEmpty else { return false }
                if isChromePhrase(line) { return false }
                if looksLikeLatinHUDChip(line) { return false }
                return true
            }
            .joined(separator: "\n")
    }
}

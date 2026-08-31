import Foundation

/// Filters App / share-sheet chrome that OCR often mistakes for highlighter vocabulary.
public enum OCRChromeFilter {
    private static let exactChrome: Set<String> = [
        "review", "library", "create", "cancel", "generate", "generate cards",
        "manage decks", "manage deck", "target deck", "deck", "add word",
        "add", "done", "close", "ok", "settings", "save", "search",
        "shared content ready", "imported from clipboard",
        "复习", "词库", "制卡", "取消", "生成", "生成卡片", "管理词库",
        "目标词库", "添加生词", "完成", "关闭", "设置", "保存", "搜索"
    ]

    public static func isChromePhrase(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        if trimmed.count == 1, !trimmed.first!.isLetter { return true }

        let key = trimmed.lowercased()
        if exactChrome.contains(key) { return true }
        if looksLikeLatinHUDChip(trimmed) { return true }

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
    public static func isPlausibleVocabularyToken(_ raw: String, in fullText: String) -> Bool {
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
        if fullText.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        let unwrapped = fullText.replacingOccurrences(
            of: #"([A-Za-z])-\s+"#,
            with: "$1",
            options: .regularExpression
        )
        if unwrapped.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        let compact = trimmed.replacingOccurrences(
            of: #"[\s\-‐‑–]+"#,
            with: "",
            options: .regularExpression
        )
        guard compact.count >= 4, compact != trimmed else { return false }
        let compactPattern = "\\b\(NSRegularExpression.escapedPattern(for: compact))\\b"
        return unwrapped.range(of: compactPattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Overlay control vs body text. Geometry / typography only — screenshots
    /// differ, so never match a list of button captions.
    public static func looksLikeOverlayControl(token: String, lineText: String, boxArea: Double) -> Bool {
        if boxArea > 0, boxArea < 0.0012 { return true }
        if looksLikeLatinHUDChip(token) { return true }
        if looksLikeStandaloneChip(token: token, line: lineText) { return true }
        return false
    }

    /// HUD chips: short ALL-CAPS Latin, no CJK, no digits/punctuation.
    public static func looksLikeLatinHUDChip(_ raw: String) -> Bool {
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
    public static func looksLikeStandaloneChip(token: String, line: String) -> Bool {
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

    public static func looksLikeChromeBlob(_ text: String) -> Bool {
        let lower = text.lowercased()
        let markers = [
            "manage decks", "generate cards", "review", "library", "create",
            "管理词库", "生成卡片", "复习", "词库", "制卡"
        ]
        let hits = markers.filter { lower.contains($0) }.count
        return hits >= 2
    }

    public static func strippingChromeLines(from text: String) -> String {
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

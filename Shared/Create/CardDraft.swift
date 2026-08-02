import Foundation

enum CardType: String, Codable, CaseIterable {
    case cloze
    case definition

    var displayName: String {
        switch self {
        case .cloze: L10n.cardTypeCloze
        case .definition: L10n.cardTypeDefinition
        }
    }
}

struct GeneratedCardDraft: Identifiable, Equatable {
    let id = UUID()
    var word: String
    var phonetic: String?
    var sentence: String
    var cardType: CardType
    var front: String
    var back: String
    var contextNote: String?
    /// Book / article / author when AI (or page header) can identify it.
    var sourceAttribution: String?
    var isSelected: Bool = true
}

enum CardContentFormatter {
    /// Plain-text back for lists / export: sense, then sentence translation.
    static func displayBack(back: String, contextNote: String?) -> String {
        let sense = trimmed(back)
        let translation = trimmed(contextNote)
        switch (sense.isEmpty, translation.isEmpty) {
        case (false, false):
            if sense.contains(translation) { return sense }
            return sense + "\n\n" + L10n.cardSentenceTranslation + "\n" + translation
        case (true, false):
            return translation
        default:
            return sense
        }
    }

    static func mergedBack(back: String, contextNote: String?) -> String {
        displayBack(back: back, contextNote: contextNote)
    }

    static func senseText(_ back: String) -> String {
        trimmed(back)
    }

    static func sentenceTranslation(_ contextNote: String?) -> String? {
        let value = stripHighlightMarkers(trimmed(contextNote))
        return value.isEmpty ? nil : value
    }

    /// Terms to emphasize in the sentence translation (marked spans first, then gloss fallback).
    static func translationHighlightTerms(contextNote: String?, sense: String) -> [String] {
        let marked = extractMarkedTerms(from: trimmed(contextNote))
        if !marked.isEmpty { return uniqueTerms(marked) }

        let plain = sentenceTranslation(contextNote) ?? ""
        guard !plain.isEmpty else { return [] }
        return uniqueTerms(glossCandidates(from: sense).filter { plain.contains($0) })
    }

    /// Strip 【…】 / 「…」 highlight markers used in AI translations.
    static func stripHighlightMarkers(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = text
        let patterns = [#"【([^】]+)】"#, #"「([^」]+)」"#]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: "$1"
            )
        }
        return result
    }

    private static func extractMarkedTerms(from text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var terms: [String] = []
        let patterns = [#"【([^】]+)】"#, #"「([^」]+)」"#]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            for match in matches where match.numberOfRanges >= 2 {
                let term = trimmed(ns.substring(with: match.range(at: 1)))
                if !term.isEmpty { terms.append(term) }
            }
        }
        return terms
    }

    /// Pull short Chinese glosses from sense text for highlighting legacy cards.
    static func glossCandidates(from sense: String) -> [String] {
        var text = trimmed(sense)
        guard !text.isEmpty else { return [] }

        for marker in ["在此句", "在本句", "这里指", "此处", "指的是", "表示"] {
            if let range = text.range(of: marker) {
                text = trimmed(String(text[..<range.lowerBound]))
                break
            }
        }
        if let period = text.firstIndex(of: "。") {
            text = trimmed(String(text[..<period]))
        }
        if let newline = text.firstIndex(of: "\n") {
            text = trimmed(String(text[..<newline]))
        }

        // Drop leading POS tags: "v. ", "adj.", "动词 ", etc.
        let posPrefixes = [
            "vt.", "vi.", "v.", "n.", "adj.", "adv.", "prep.", "conj.", "pron.", "num.",
            "动词", "名词", "形容词", "副词", "介词", "连词", "代词"
        ]
        for prefix in posPrefixes {
            if text.lowercased().hasPrefix(prefix.lowercased()) {
                text = trimmed(String(text.dropFirst(prefix.count)))
                if text.hasPrefix(".") || text.hasPrefix("。") || text.hasPrefix("：") || text.hasPrefix(":") {
                    text = trimmed(String(text.dropFirst()))
                }
                break
            }
        }

        let separators = CharacterSet(charactersIn: "，,、/;；|/｜")
        return text
            .components(separatedBy: separators)
            .map { trimmed($0).trimmingCharacters(in: .punctuationCharacters) }
            .filter { candidate in
                guard candidate.count >= 1, candidate.count <= 12 else { return false }
                return cjkRatio(candidate) >= 0.6
            }
    }

    private static func uniqueTerms(_ terms: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for term in terms {
            let key = term.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(term)
        }
        // Longer first so nested overlaps prefer the fuller gloss.
        return result.sorted { $0.count > $1.count }
    }

    private static func trimmed(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Review / preview front: definition cards always prefer the full source sentence.
    static func displayFront(
        front: String,
        sentence: String,
        word: String,
        cardType: CardType
    ) -> String {
        let trimmedFront = front.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSentence = sentence.trimmingCharacters(in: .whitespacesAndNewlines)

        switch cardType {
        case .cloze:
            return trimmedFront.isEmpty ? trimmedSentence : trimmedFront
        case .definition:
            if !trimmedSentence.isEmpty {
                return trimmedSentence
            }
            if isWordOnlyFront(trimmedFront, word: word) {
                return trimmedFront
            }
            return trimmedFront
        }
    }

    /// Normalize generated/imported fronts so definition cards store the sentence.
    static func normalizedFront(
        front: String,
        sentence: String,
        word: String,
        cardType: CardType
    ) -> String {
        displayFront(front: front, sentence: sentence, word: word, cardType: cardType)
    }

    /// Split old single-field backs into sense + sentence translation when possible.
    static func splitLegacyBack(_ raw: String) -> (sense: String, translation: String?) {
        let text = trimmed(raw)
        guard !text.isEmpty else { return ("", nil) }

        let markers = [
            "句子翻译",
            "Sentence translation",
            "整句翻译",
            "译文：",
            "译文:",
            "翻译：",
            "翻译:",
            "句译："
        ]
        for marker in markers {
            guard let range = text.range(of: marker, options: .caseInsensitive) else { continue }
            let sense = trimmed(String(text[..<range.lowerBound]))
            var translation = trimmed(String(text[range.upperBound...]))
            while translation.hasPrefix("：") || translation.hasPrefix(":") || translation.hasPrefix("\n") {
                translation = trimmed(String(translation.dropFirst()))
            }
            if !translation.isEmpty {
                return (sense.isEmpty ? text : sense, translation)
            }
        }

        let parts = text
            .components(separatedBy: "\n\n")
            .map(trimmed)
            .filter { !$0.isEmpty }
        if parts.count >= 2 {
            let last = parts[parts.count - 1]
            let head = parts.dropLast().joined(separator: "\n\n")
            if looksLikeSentenceTranslation(last), !looksLikeSentenceTranslation(head) || cjkRatio(last) >= 0.45 {
                return (head, last)
            }
        }

        return (text, nil)
    }

    private static func isWordOnlyFront(_ front: String, word: String) -> Bool {
        let compactFront = front
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters)
        let compactWord = word
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters)
        guard !compactFront.isEmpty else { return true }
        if compactFront.caseInsensitiveCompare(compactWord) == .orderedSame {
            return true
        }
        // Short prompt like "What does mitigate mean?" still lacks source context.
        return !front.contains(where: { $0.isWhitespace }) && front.count <= max(word.count + 4, 24)
    }

    private static func looksLikeSentenceTranslation(_ text: String) -> Bool {
        let value = trimmed(text)
        guard value.count >= 8 else { return false }
        // Prefer Chinese full-sentence style endings / high CJK density.
        if value.hasSuffix("。") || value.hasSuffix("！") || value.hasSuffix("？") {
            return cjkRatio(value) >= 0.35
        }
        return cjkRatio(value) >= 0.55 && value.count >= 12
    }

    private static func cjkRatio(_ text: String) -> Double {
        guard !text.isEmpty else { return 0 }
        let cjk = text.unicodeScalars.filter { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
                || (0x3400...0x4DBF).contains(scalar.value)
                || (0x3000...0x303F).contains(scalar.value)
        }.count
        return Double(cjk) / Double(text.count)
    }
}

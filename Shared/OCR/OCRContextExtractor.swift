import Foundation

/// Build import units of (sentence + words) from full-page OCR + highlight hits.
enum OCRContextExtractor {
    /// Short page-header hint for AI source attribution (titles / bylines).
    static func sourceHint(from fullText: String) -> String? {
        let lines = fullText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }

        var hints: [String] = []
        for line in lines.prefix(8) {
            if line.count > 80 { break }
            // Stop once body prose begins (long lowercase-heavy line).
            let letterCount = line.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
            let lowerCount = line.unicodeScalars.filter { CharacterSet.lowercaseLetters.contains($0) }.count
            if letterCount >= 24, Double(lowerCount) / Double(max(letterCount, 1)) > 0.55 {
                break
            }
            hints.append(line)
            if hints.count >= 5 { break }
        }
        let joined = hints.joined(separator: " · ")
        return joined.isEmpty ? nil : joined
    }

    /// Soft-join wrapped lines, then map each word to its containing sentence.
    static func importUnits(fullText: String, highlightedWords: [String]) -> [OCRImportUnit] {
        let words = highlightedWords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return [] }

        let normalized = softJoinLines(fullText)
        guard !normalized.isEmpty else { return [] }

        var sentenceOrder: [String] = []
        var wordsBySentence: [String: [String]] = [:]

        for word in words {
            let sentences = sentencesContainingHighlight(word, in: normalized)
            guard !sentences.isEmpty else { continue }
            for sentence in sentences {
                if wordsBySentence[sentence] == nil {
                    sentenceOrder.append(sentence)
                    wordsBySentence[sentence] = []
                }
                var list = wordsBySentence[sentence] ?? []
                if !list.contains(where: { $0.caseInsensitiveCompare(word) == .orderedSame }) {
                    list.append(word)
                    wordsBySentence[sentence] = list
                }
            }
        }

        return sentenceOrder.compactMap { sentence in
            guard let list = wordsBySentence[sentence], !list.isEmpty else { return nil }
            return OCRImportUnit(sentence: sentence, words: list)
        }
    }

    /// Locate every sentence that contains this highlight (phrase, or significant tokens if phrase OCR-mismatched).
    private static func sentencesContainingHighlight(_ highlight: String, in text: String) -> [String] {
        if let sentence = sentenceContaining(highlight, in: text) {
            return [sentence]
        }

        // Multi-word highlighter phrases often diverge slightly from OCR spacing/hyphens.
        let parts = highlight
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "‐" })
            .map { String($0).trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.count >= 4 }
        var found: [String] = []
        var seen = Set<String>()
        for part in parts {
            guard let sentence = sentenceContaining(part, in: text) else { continue }
            let key = sentence.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            found.append(sentence)
        }
        return found
    }

    /// Join OCR line wraps into reading order without treating every newline as a sentence end.
    static func softJoinLines(_ text: String) -> String {
        joinParagraphs(text, separator: " ")
    }

    /// Create UI text: same paragraph logic as `softJoinLines`, but blank lines between blocks.
    static func displayText(from text: String) -> String {
        joinParagraphs(text, separator: "\n\n")
    }

    private static func joinParagraphs(_ text: String, separator: String) -> String {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return "" }

        var parts: [String] = []
        var buffer = lines[0]
        for line in lines.dropFirst() {
            if shouldBreakParagraph(before: line, after: buffer) {
                parts.append(buffer)
                buffer = line
            } else if let joined = joinHyphenatedWrap(buffer: buffer, nextLine: line) {
                buffer = joined
            } else if buffer.last.map({ $0.isWhitespace }) == true {
                buffer += line
            } else {
                buffer += " " + line
            }
        }
        parts.append(buffer)

        return parts
            .map { normalizeInlineSpaces($0) }
            .joined(separator: separator)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeInlineSpaces(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"[^\S\n]{2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(
                of: #"([A-Za-z])-\s+([a-z])"#,
                with: "$1$2",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `pret-` + `ty` / `pret` + `-ty` → `pretty` (common book OCR wrap).
    private static func joinHyphenatedWrap(buffer: String, nextLine: String) -> String? {
        let hyphen: Set<Character> = ["-", "‐", "‑", "–"]
        if let last = buffer.last, hyphen.contains(last) {
            let stem = String(buffer.dropLast())
            let rest = String(nextLine.drop(while: { hyphen.contains($0) || $0.isWhitespace }))
            guard stem.last?.isLetter == true, rest.first?.isLetter == true else { return nil }
            return stem + rest
        }
        if let first = nextLine.first, hyphen.contains(first) {
            let rest = String(nextLine.drop(while: { hyphen.contains($0) || $0.isWhitespace }))
            guard buffer.last?.isLetter == true, rest.first?.isLetter == true else { return nil }
            return buffer + rest
        }
        return nil
    }

    static func sentenceContaining(_ word: String, in text: String) -> String? {
        guard let match = rangeOfWord(word, in: text) else { return nil }

        var start = match.lowerBound
        while start > text.startIndex {
            let prev = text.index(before: start)
            if isSentenceTerminator(at: prev, in: text) {
                start = text.index(after: prev)
                break
            }
            start = prev
        }
        // Skip closing punctuation left after a terminator: `exams.) In fact` → `In fact`
        while start < text.endIndex, isTrailingCloser(text[start]) {
            start = text.index(after: start)
        }
        while start < text.endIndex, text[start].isWhitespace {
            start = text.index(after: start)
        }

        var end = match.upperBound
        while end < text.endIndex {
            if isSentenceTerminator(at: end, in: text) {
                end = text.index(after: end)
                // Include trailing quote/paren after the stop: `grateful."`
                while end < text.endIndex, isTrailingCloser(text[end]) {
                    end = text.index(after: end)
                }
                break
            }
            end = text.index(after: end)
        }

        let sentence = String(text[start..<end])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty else { return nil }
        // Avoid importing a whole chapter when boundaries are missing.
        if sentence.count > 420 {
            return windowAround(match, in: text, radius: 160)
        }
        return sentence
    }

    /// `.` / `。` etc., but not the dots inside an ellipsis (`...` / `…`).
    private static func isSentenceTerminator(at index: String.Index, in text: String) -> Bool {
        let ch = text[index]
        let terminators: Set<Character> = [".", "!", "?", "。", "！", "？", "…"]
        guard terminators.contains(ch) else { return false }
        if ch == "." {
            if index > text.startIndex {
                let prev = text.index(before: index)
                if text[prev] == "." { return false }
            }
            let next = text.index(after: index)
            if next < text.endIndex, text[next] == "." { return false }
        }
        return true
    }

    private static func isTrailingCloser(_ ch: Character) -> Bool {
        [")", "]", "}", "\"", "'", "”", "’", "»"].contains(ch)
    }

    private static func shouldBreakParagraph(before line: String, after buffer: String) -> Bool {
        if endsWithSentenceTerminator(buffer) { return true }
        // ALL-CAPS short titles / bylines — keep separate from body.
        if line.count <= 48, line.uppercased() == line, line.contains(where: \.isLetter) {
            return true
        }
        if buffer.count <= 48, buffer.uppercased() == buffer, buffer.contains(where: \.isLetter) {
            return true
        }
        return false
    }

    private static func endsWithSentenceTerminator(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.indices.last else { return false }
        // Allow `grateful."` / `exams.)` as paragraph ends.
        if isTrailingCloser(trimmed[last]) {
            var idx = last
            while idx > trimmed.startIndex, isTrailingCloser(trimmed[idx]) {
                idx = trimmed.index(before: idx)
            }
            return isSentenceTerminator(at: idx, in: trimmed)
        }
        return isSentenceTerminator(at: last, in: trimmed)
    }

    private static func rangeOfWord(_ word: String, in text: String) -> Range<String.Index>? {
        if let range = text.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) {
            return range
        }
        // OCR often normalizes curly apostrophes.
        let foldedWord = word
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
        let foldedText = text
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
        guard let foldedRange = foldedText.range(
            of: foldedWord,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) else { return nil }

        let lower = text.index(
            text.startIndex,
            offsetBy: foldedText.distance(from: foldedText.startIndex, to: foldedRange.lowerBound)
        )
        let upper = text.index(
            text.startIndex,
            offsetBy: foldedText.distance(from: foldedText.startIndex, to: foldedRange.upperBound)
        )
        return lower..<upper
    }

    private static func windowAround(
        _ range: Range<String.Index>,
        in text: String,
        radius: Int
    ) -> String {
        let startOffset = max(0, text.distance(from: text.startIndex, to: range.lowerBound) - radius)
        let endOffset = min(
            text.count,
            text.distance(from: text.startIndex, to: range.upperBound) + radius
        )
        let start = text.index(text.startIndex, offsetBy: startOffset)
        let end = text.index(text.startIndex, offsetBy: endOffset)
        return String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

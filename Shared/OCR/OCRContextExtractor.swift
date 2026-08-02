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
            guard let sentence = sentenceContaining(word, in: normalized) else { continue }
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

        return sentenceOrder.compactMap { sentence in
            guard let list = wordsBySentence[sentence], !list.isEmpty else { return nil }
            return OCRImportUnit(sentence: sentence, words: list)
        }
    }

    /// Join OCR line wraps into reading order without treating every newline as a sentence end.
    static func softJoinLines(_ text: String) -> String {
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
            .joined(separator: " ")
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(
                // Book OCR wrap left mid-line: "pret- ty" → "pretty"
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

        let terminators: Set<Character> = [".", "!", "?", "。", "！", "？", "…"]
        var start = match.lowerBound
        while start > text.startIndex {
            let prev = text.index(before: start)
            if terminators.contains(text[prev]) {
                start = text.index(after: prev)
                break
            }
            start = prev
        }

        var end = match.upperBound
        while end < text.endIndex {
            let ch = text[end]
            end = text.index(after: end)
            if terminators.contains(ch) { break }
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
        guard let last = text.last else { return false }
        return [".", "!", "?", "。", "！", "？", "…"].contains(last)
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

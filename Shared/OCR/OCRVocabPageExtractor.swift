import Foundation

/// Detect a photographed vocabulary-list page (CET / word book) and turn
/// headwords into import units so Create can pre-select them.
///
/// Highlighter hits still win: this only runs when the page has no usable marks.
enum OCRVocabPageExtractor {
    struct Page: Equatable, Sendable {
        var units: [OCRImportUnit]

        var words: [String] {
            var seen = Set<String>()
            var ordered: [String] = []
            for word in units.flatMap(\.words) {
                let key = word.lowercased()
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                ordered.append(word)
            }
            return ordered
        }
    }

    private static let maxHeadwords = 40

    private static let particles: Set<String> = [
        "up", "out", "in", "on", "off", "down", "away", "over", "back",
        "after", "for", "to", "with", "into", "through", "around", "about",
        "across", "along", "aside", "apart", "by", "of"
    ]

    private static let stopwords: Set<String> = [
        "a", "an", "the", "of", "to", "in", "on", "at", "for", "and", "or", "but",
        "as", "by", "with", "from", "into", "over", "onto", "upon", "per", "via",
        "is", "are", "was", "were", "be", "been", "am", "do", "does", "did",
        "not", "no", "so", "if", "than", "then", "that", "this", "these", "those",
        "it", "its", "his", "her", "their", "our", "my", "your", "he", "she",
        "we", "they", "you", "i", "me", "him", "them", "us",
        "unit", "lesson", "chapter", "page", "word", "words", "list", "vocabulary",
        "meaning", "example", "examples", "synonym", "synonyms", "answer", "key",
        "cet", "toefl", "ielts", "nawl", "ngsl", "new", "old"
    ]

    private static let posToken = #"(?:n|v|vt|vi|adj|adv|prep|conj|pron|art|num|aux|det|modal|phr|phr\.v|a|ad|int|abbr)[.\．]"#

    static func extract(fullText: String, leftColumnWords: [String] = []) -> Page? {
        let lines = fullText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !isPageChrome($0) }
        guard !lines.isEmpty else { return nil }

        var entries = parseEntries(from: lines)
        mergeLeftColumn(leftColumnWords, into: &entries, lines: lines)
        sortByAppearance(entries: &entries, in: fullText)

        guard looksLikeVocabPage(entries: entries, lines: lines) else { return nil }

        let capped = Array(entries.prefix(maxHeadwords))
        let units = capped.compactMap { entry -> OCRImportUnit? in
            let sentence = cardSentence(for: entry)
            guard !sentence.isEmpty else { return nil }
            return OCRImportUnit(sentence: sentence, words: [entry.word])
        }
        guard units.count >= 4 else { return nil }
        return Page(units: units)
    }

    /// First Latin token on a short left-aligned line — typical dictionary headword column.
    static func looksLikeHeadword(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lemma = normalizeLemma(trimmed) else { return false }
        return isPlausibleLemma(lemma)
    }

    // MARK: - Parse

    private struct Entry {
        var word: String
        var gloss: String
        var example: String?
        var hasDictionaryCue: Bool
    }

    private struct HeadMatch {
        var word: String
        var rest: String
        var hasDictionaryCue: Bool
    }

    private static func parseEntries(from lines: [String]) -> [Entry] {
        var entries: [Entry] = []
        var seen = Set<String>()
        var index = 0
        while index < lines.count {
            let line = lines[index]
            let columns = splitColumnEntries(line)
            if columns.count >= 2 {
                for match in columns {
                    appendEntry(
                        word: match.word,
                        gloss: match.rest,
                        example: nil,
                        hasDictionaryCue: true,
                        seen: &seen,
                        entries: &entries
                    )
                }
                index += 1
                continue
            }

            guard let head = parseHeadwordLine(line) else {
                index += 1
                continue
            }

            var gloss = head.rest
            var example: String?
            var cursor = index + 1
            var consumed = 0
            while cursor < lines.count, consumed < 5 {
                let next = lines[cursor]
                if parseHeadwordLine(next) != nil || splitColumnEntries(next).count >= 2 {
                    break
                }
                if isPageChrome(next) || looksLikeIPA(next) {
                    cursor += 1
                    consumed += 1
                    continue
                }
                if looksLikeExample(next, headword: head.word) {
                    if example == nil { example = next }
                } else if looksLikeGloss(next) {
                    gloss = gloss.isEmpty ? next : gloss + " " + next
                } else if looksLikeEnglishSentence(next), example == nil {
                    example = next
                } else {
                    break
                }
                cursor += 1
                consumed += 1
            }

            appendEntry(
                word: head.word,
                gloss: stripIPA(gloss),
                example: example,
                hasDictionaryCue: head.hasDictionaryCue || looksLikeGloss(gloss) || example != nil,
                seen: &seen,
                entries: &entries
            )
            index = cursor
        }
        return entries
    }

    private static func appendEntry(
        word: String,
        gloss: String,
        example: String?,
        hasDictionaryCue: Bool,
        seen: inout Set<String>,
        entries: inout [Entry]
    ) {
        let key = word.lowercased()
        guard !seen.contains(key) else { return }
        seen.insert(key)
        entries.append(
            Entry(
                word: word,
                gloss: gloss.trimmingCharacters(in: .whitespacesAndNewlines),
                example: example,
                hasDictionaryCue: hasDictionaryCue
            )
        )
    }

    private static func parseHeadwordLine(_ line: String) -> HeadMatch? {
        let stripped = stripListPrefix(line)
        guard !stripped.isEmpty, !isPageChrome(stripped) else { return nil }
        if looksLikeEnglishSentence(stripped), !hasPOS(stripped), !containsCJK(stripped) {
            return nil
        }

        let pattern = #"^([A-Za-z][A-Za-z\-']{1,22})(?:\s+(up|out|in|on|off|down|away|over|back|after|for|to|with|into|through|around|about|across|along))?(?=\s|$|/|\[|\()"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: stripped, range: NSRange(stripped.startIndex..., in: stripped)),
              let wordRange = Range(match.range(at: 1), in: stripped)
        else { return nil }

        var lemma = String(stripped[wordRange])
        if match.range(at: 2).location != NSNotFound,
           let particleRange = Range(match.range(at: 2), in: stripped) {
            let particle = String(stripped[particleRange]).lowercased()
            if particles.contains(particle) {
                lemma += " " + particle
            }
        }

        guard isPlausibleLemma(lemma) else { return nil }

        let restStart = match.range(at: 0).location + match.range(at: 0).length
        let restNS = (stripped as NSString).substring(from: min(restStart, (stripped as NSString).length))
        let rest = stripIPA(restNS).trimmingCharacters(in: .whitespacesAndNewlines)
        let cue = hasPOS(stripped) || containsCJK(stripped) || looksLikeIPA(stripped)
        return HeadMatch(word: lemma, rest: rest, hasDictionaryCue: cue)
    }

    /// Two-column dictionary lines: `abandon 放弃  ability 能力`.
    private static func splitColumnEntries(_ line: String) -> [HeadMatch] {
        guard containsCJK(line) else { return [] }
        let pattern = #"\b([A-Za-z][A-Za-z\-']{2,22})(?:\s+/[^/\n]{0,40}/)?(?:\s+"#
            + posToken
            + #")?\s*([\u4E00-\u9FFF]{1,16})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = line as NSString
        let matches = regex.matches(in: line, range: NSRange(location: 0, length: ns.length))
        guard matches.count >= 2 else { return [] }

        var result: [HeadMatch] = []
        var seen = Set<String>()
        for match in matches {
            guard let wordRange = Range(match.range(at: 1), in: line) else { continue }
            let word = String(line[wordRange])
            guard isPlausibleLemma(word) else { continue }
            let key = word.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            var gloss = ""
            if match.numberOfRanges > 2, match.range(at: match.numberOfRanges - 1).location != NSNotFound,
               let glossRange = Range(match.range(at: match.numberOfRanges - 1), in: line) {
                gloss = String(line[glossRange])
            }
            result.append(HeadMatch(word: word, rest: gloss, hasDictionaryCue: true))
        }
        return result.count >= 2 ? result : []
    }

    private static func mergeLeftColumn(
        _ leftColumnWords: [String],
        into entries: inout [Entry],
        lines: [String]
    ) {
        var seen = Set(entries.map { $0.word.lowercased() })
        for raw in leftColumnWords {
            guard let lemma = normalizeLemma(raw), isPlausibleLemma(lemma) else { continue }
            let key = lemma.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            let line = lines.first(where: {
                $0.range(of: lemma, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            })
            let rest = line.map { stripIPA(stripListPrefix($0)) } ?? ""
            let gloss: String
            if let range = rest.range(of: lemma, options: .caseInsensitive) {
                gloss = String(rest[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                gloss = rest
            }
            entries.append(
                Entry(
                    word: lemma,
                    gloss: gloss,
                    example: nil,
                    hasDictionaryCue: hasPOS(gloss) || containsCJK(gloss)
                )
            )
        }
    }

    private static func looksLikeVocabPage(entries: [Entry], lines: [String]) -> Bool {
        guard entries.count >= 4 else { return false }

        let cued = entries.filter(\.hasDictionaryCue).count
        let posHits = lines.filter(hasPOS).count
        let cjkHits = entries.filter { containsCJK($0.gloss) || ($0.example.map(containsCJK) ?? false) }.count
        let longProse = lines.filter { looksLikeEnglishSentence($0) && !hasPOS($0) && !containsCJK($0) }.count

        if cued >= 4 { return true }
        if posHits >= 3, entries.count >= 4 { return true }
        if cjkHits >= 3, entries.count >= 4 { return true }

        // Bare word list (one lemma per line, almost no prose).
        let shortBare = entries.filter { $0.gloss.isEmpty && $0.example == nil }.count
        if shortBare >= 6, longProse <= 1, Double(entries.count) / Double(max(lines.count, 1)) >= 0.45 {
            return true
        }
        return false
    }

    private static func cardSentence(for entry: Entry) -> String {
        if let example = entry.example?.trimmingCharacters(in: .whitespacesAndNewlines),
           example.count >= 12 {
            if example.range(of: entry.word, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                return example
            }
            return "\(entry.word). \(example)"
        }

        let gloss = entry.gloss.trimmingCharacters(in: .whitespacesAndNewlines)
        var text = gloss.isEmpty ? entry.word : "\(entry.word) — \(gloss)"
        if let last = text.last, !".。！？!?".contains(last) {
            text += "."
        }
        return text
    }

    // MARK: - Line tests

    private static func isPlausibleLemma(_ raw: String) -> Bool {
        let lemma = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = lemma.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let first = parts.first else { return false }
        guard let normalized = normalizeLemma(first) else { return false }
        if parts.count == 2 {
            guard particles.contains(parts[1].lowercased()) else { return false }
        } else if parts.count > 2 {
            return false
        }

        if stopwords.contains(normalized.lowercased()) { return false }
        if OCRChromeFilter.isChromePhrase(lemma) { return false }
        if OCRChromeFilter.looksLikeLatinHUDChip(lemma) { return false }
        return true
    }

    private static func normalizeLemma(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
        guard trimmed.count >= 3, trimmed.count <= 24 else { return nil }
        let letters = trimmed.filter(\.isLetter)
        guard letters.count >= 3 else { return nil }
        guard trimmed.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) || $0 == "-" || $0 == "'" || $0 == "’" }) else {
            return nil
        }
        return trimmed.replacingOccurrences(of: "’", with: "'")
    }

    private static func stripListPrefix(_ line: String) -> String {
        let pattern = #"^(?:(?:\d{1,3}|[A-Za-z])[\.、\)\]:]|[•·\-—–])\s+"#
        return line.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }

    private static func stripIPA(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"/[^/\n]{1,48}/"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\[[^\]\n]{1,48}\]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isPageChrome(_ line: String) -> Bool {
        let key = line.lowercased()
        if line.count <= 48 {
            let markers = [
                "word list", "vocabulary", "unit ", "lesson ", "chapter ",
                "单词表", "词汇表", "词表", "cet-4", "cet-6", "cet4", "cet6",
                "toefl", "ielts", "四级", "六级", "答案", "page "
            ]
            if markers.contains(where: { key.contains($0) }) { return true }
        }
        if line.range(of: #"^\d{1,4}$"#, options: .regularExpression) != nil { return true }
        return OCRChromeFilter.isChromePhrase(line)
    }

    private static func sortByAppearance(entries: inout [Entry], in fullText: String) {
        entries.sort { lhs, rhs in
            let left = fullText.range(of: lhs.word, options: [.caseInsensitive, .diacriticInsensitive])
            let right = fullText.range(of: rhs.word, options: [.caseInsensitive, .diacriticInsensitive])
            switch (left, right) {
            case let (l?, r?):
                return l.lowerBound < r.lowerBound
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return lhs.word.localizedCaseInsensitiveCompare(rhs.word) == .orderedAscending
            }
        }
    }

    private static func hasPOS(_ text: String) -> Bool {
        let pattern = #"(?<![A-Za-z])"# + posToken
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
    }

    private static func looksLikeIPA(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.range(of: #"^[/\[].+[/\]]$"#, options: .regularExpression) != nil { return true }
        let letters = trimmed.filter(\.isLetter)
        guard letters.count >= 3, letters.count <= 18, !containsCJK(trimmed) else { return false }
        // Stress / schwa-ish OCR junk: e'baendan, əˈbændən
        return trimmed.contains("'") || trimmed.contains("ˈ") || trimmed.contains("ˌ") || trimmed.contains("ə")
    }

    private static func looksLikeGloss(_ text: String) -> Bool {
        if containsCJK(text) { return true }
        if hasPOS(text), !looksLikeEnglishSentence(text) { return true }
        return false
    }

    private static func looksLikeExample(_ text: String, headword: String) -> Bool {
        guard looksLikeEnglishSentence(text) else { return false }
        return text.range(of: headword, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            || text.split(whereSeparator: \.isWhitespace).count >= 6
    }

    private static func looksLikeEnglishSentence(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 24 else { return false }
        let tokens = trimmed.split(whereSeparator: \.isWhitespace)
        guard tokens.count >= 5 else { return false }
        let latinWords = tokens.filter { token in
            token.first?.isLetter == true && token.unicodeScalars.allSatisfy {
                CharacterSet.letters.contains($0) || $0 == "'" || $0 == "’" || $0 == "-"
            }
        }
        return latinWords.count >= 5
    }
}

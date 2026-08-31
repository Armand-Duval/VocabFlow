import Foundation

/// Merge OCR tokens under highlighter ink into vocabulary phrases.
///
/// Book highlighters often break a single idiom across lines and leave short
/// glue words (`a` / `of`) under-inked. We keep one span whenever hard hits are
/// connected by only glue / weak-ink tokens (including wraps).
public enum HighlightPhraseMerger {
    public struct Token: Equatable, Sendable {
        public let text: String
        public let lineIndex: Int
        public let coverage: Double
        public let minX: Double
        public let maxX: Double

        public init(
            text: String,
            lineIndex: Int,
            coverage: Double,
            minX: Double = 0,
            maxX: Double = 1
        ) {
            self.text = text
            self.lineIndex = lineIndex
            self.coverage = coverage
            self.minX = minX
            self.maxX = maxX
        }
    }

    public static let hitThreshold = 0.40
    /// Soft ink — enough to sit inside a highlighter stroke.
    public static let weakThreshold = 0.12

    private static let glueWords: Set<String> = [
        "a", "an", "the", "of", "to", "in", "on", "at", "for", "and", "or", "but",
        "as", "by", "with", "from", "into", "over", "onto", "upon", "per", "via",
        "is", "are", "was", "were", "be", "been", "am", "do", "does", "did",
        "not", "no", "so", "if", "than", "then", "that", "this", "these", "those",
        "it", "its", "his", "her", "their", "our", "my", "your",
    ]

    public static func merge(
        tokens: [Token],
        hitThreshold: Double = hitThreshold,
        pageText: String = ""
    ) -> [String] {
        guard !tokens.isEmpty else { return [] }

        // Never seed on glue — yellow bleed often paints "of"/"my" more than the headword.
        let hard: [Bool] = tokens.map { token in
            let key = normalizedGlueKey(token.text)
            if glueWords.contains(key) { return false }
            if isHyphenOnly(token.text) { return false }
            if token.coverage >= hitThreshold { return true }
            let letters = token.text.filter(\.isLetter).count
            // Line-wrap stems (`dis-`) are short; still count if they carry marker ink.
            if tokenEndsWithHyphen(token.text), letters >= 2, token.coverage >= weakThreshold {
                return true
            }
            // Long pale markers (e.g. simplicity at the end of a stroke) sit below 0.40.
            if token.coverage >= 0.16, letters >= 7 { return true }
            // Mid ink on a real content word (e.g. clincher ~0.22) still counts as a marker.
            if token.coverage >= 0.22, letters >= 4 { return true }
            return false
        }
        guard hard.contains(true) else { return [] }

        let hardCount = hard.filter { $0 }.count
        if Double(hardCount) / Double(tokens.count) >= 0.85, tokens.count >= 8 {
            return []
        }

        // Seed with hard hits, then fill every soft/glue gap between nearby hard hits.
        var include = hard
        fillGapsBetweenHardHits(
            include: &include,
            tokens: tokens,
            hard: hard,
            maxSpan: 8,
            pageText: pageText
        )

        var phrases: [String] = []
        var runStart: Int?
        for index in tokens.indices {
            if include[index] {
                if let start = runStart,
                   index > 0,
                   shouldSplitRun(
                    previous: index - 1,
                    current: index,
                    tokens: tokens,
                    hard: hard,
                    include: include,
                    pageText: pageText
                   ) {
                    flush(tokens[start..<index], into: &phrases)
                    runStart = index
                } else if runStart == nil {
                    runStart = index
                }
            } else if let start = runStart {
                flush(tokens[start..<index], into: &phrases)
                runStart = nil
            }
        }
        if let start = runStart {
            flush(tokens[start...], into: &phrases)
        }

        var seen = Set<String>()
        var unique: [String] = []
        for phrase in phrases {
            let key = phrase.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            unique.append(phrase)
        }
        return unique
    }

    /// If two hard hits are close and only soft/glue tokens sit between them, mark the gap included.
    private static func fillGapsBetweenHardHits(
        include: inout [Bool],
        tokens: [Token],
        hard: [Bool],
        maxSpan: Int,
        pageText: String
    ) {
        let hardIndices = hard.indices.filter { hard[$0] }
        guard hardIndices.count >= 2 else { return }

        for pair in zip(hardIndices, hardIndices.dropFirst()) {
            let left = pair.0
            let right = pair.1
            let gap = right - left
            guard gap > 1, gap <= maxSpan else { continue }
            guard canJoinHardHits(left: left, right: right, tokens: tokens, pageText: pageText) else { continue }

            for i in (left + 1)..<right {
                include[i] = true
            }
        }
    }

    private static func canJoinHardHits(
        left: Int,
        right: Int,
        tokens: [Token],
        pageText: String
    ) -> Bool {
        let leftToken = tokens[left]
        let rightToken = tokens[right]

        let lineDelta = rightToken.lineIndex - leftToken.lineIndex
        guard lineDelta == 0 || lineDelta == 1 else { return false }

        if lineDelta == 1 {
            guard isWrapContinuation(from: leftToken, to: rightToken, pageText: pageText) else { return false }
        } else {
            let gapX = rightToken.minX - leftToken.maxX
            guard gapX <= 0.10 else { return false }
        }

        for i in (left + 1)..<right {
            guard isGapToken(tokens[i]) else { return false }
        }
        return true
    }

    private static func shouldSplitRun(
        previous: Int,
        current: Int,
        tokens: [Token],
        hard: [Bool],
        include: [Bool],
        pageText: String
    ) -> Bool {
        guard include[previous], include[current] else { return false }
        if !hard[previous] || !hard[current] { return false }
        let a = tokens[previous]
        let b = tokens[current]
        if a.lineIndex == b.lineIndex { return false }
        return !isWrapContinuation(from: a, to: b, pageText: pageText)
    }

    private static func isWrapContinuation(from a: Token, to b: Token, pageText: String) -> Bool {
        guard b.lineIndex == a.lineIndex + 1 else { return false }
        // If the two shards form a real page word, treat as a typesetting wrap
        // even when the hyphen or margins are messy (`dis-` + `pensed` → dispensed).
        if pageContainsJoinedWord(a.text, b.text, in: pageText) {
            return true
        }
        if tokenEndsWithHyphen(a.text), b.minX <= 0.62 {
            return true
        }
        if shouldStitchWrappedStem(left: a.text, right: b.text), b.minX <= 0.62, a.maxX >= 0.48 {
            return true
        }
        return b.minX <= 0.50 && a.maxX >= 0.68
    }

    private static func pageContainsJoinedWord(_ left: String, _ right: String, in pageText: String) -> Bool {
        let compact = stripTrailingHyphen(left).filter(\.isLetter)
            + right.filter { !$0.isWhitespace && !isHyphen($0) && $0.isLetter }
        guard compact.count >= 6 else { return false }
        return pageSpelling(of: compact, in: unwrappedPage(pageText)) != nil
    }

    private static func isGapToken(_ token: Token) -> Bool {
        // Only bridge tokens that actually sit in highlighter ink. Zero-ink glue
        // ("were" between two marked headwords) is a separate marker gap.
        if isHyphenOnly(token.text) { return true }
        return token.coverage >= weakThreshold
    }

    private static func normalizedGlueKey(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
    }

    private static func flush<S: Collection>(
        _ parts: S,
        into phrases: inout [String]
    ) where S.Element == Token {
        let tokens = Array(parts)
        guard !tokens.isEmpty else { return }

        let joined: String
        if tokens.allSatisfy({ isMostlyCJK($0.text) }) {
            joined = tokens.map(\.text).joined()
        } else {
            joined = joinLatinPhrase(tokens)
        }
        let trimmed = joined.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 1, trimmed.count <= 72 else { return }
        phrases.append(trimmed)
    }

    /// Join highlighter spans; stitch book wraps (`dis-` + `pensed` → `dispensed`).
    private static func joinLatinPhrase(_ tokens: [Token]) -> String {
        var joined = tokens[0].text
        for index in 1..<tokens.count {
            let previous = tokens[index - 1]
            let current = tokens[index]
            if isHyphenOnly(current.text) {
                if !tokenEndsWithHyphen(joined) { joined += "-" }
                continue
            }
            let wrapped = current.lineIndex == previous.lineIndex + 1
            if let merged = joinHyphenated(left: joined, right: current.text, wrapped: wrapped) {
                joined = merged
            } else if wrapped, shouldStitchWrappedStem(left: previous.text, right: current.text) {
                joined = stripTrailingHyphen(joined) + String(
                    current.text.drop(while: { isHyphen($0) || $0.isWhitespace })
                )
            } else {
                joined += " " + current.text
            }
        }
        return joined
    }

    private static func joinHyphenated(left: String, right: String, wrapped: Bool) -> String? {
        guard tokenEndsWithHyphen(left) else { return nil }
        let stem = String(left.dropLast())
        let rest = String(right.drop(while: { isHyphen($0) || $0.isWhitespace }))
        guard stem.last?.isLetter == true, rest.first?.isLetter == true else { return nil }
        // Wrap: drop the hyphen. Same-line compounds keep it (`well-known`).
        return wrapped ? stem + rest : stem + "-" + rest
    }

    /// Vision often drops the wrap hyphen, leaving `dis` + `pensed` on two lines.
    private static func shouldStitchWrappedStem(left: String, right: String) -> Bool {
        let stem = stripTrailingHyphen(left).filter(\.isLetter)
        let rest = right.filter(\.isLetter)
        guard stem.count >= 2, stem.count <= 5, rest.count >= 3 else { return false }
        return stem.unicodeScalars.allSatisfy { $0.isASCII && CharacterSet.letters.contains($0) }
            && rest.unicodeScalars.allSatisfy { $0.isASCII && CharacterSet.letters.contains($0) }
    }

    /// Map OCR shards onto real page words (`dis pensed` → `dispensed`).
    public static func refine(_ phrases: [String], against pageText: String) -> [String] {
        let unwrapped = unwrappedPage(pageText)
        let stitched = stitchWrapPhrases(phrases, in: unwrapped)
        var seen = Set<String>()
        var unique: [String] = []
        for phrase in stitched {
            let resolved = resolvePhrase(phrase, in: unwrapped)
            let key = resolved.lowercased()
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            unique.append(resolved)
        }
        return unique
    }

    /// Adjacent wrap shards become one word when that word exists on the page.
    private static func stitchWrapPhrases(_ phrases: [String], in pageText: String) -> [String] {
        guard phrases.count >= 2 else { return phrases }
        var result: [String] = []
        var index = 0
        while index < phrases.count {
            if index + 1 < phrases.count {
                let left = phrases[index]
                let right = phrases[index + 1]
                if pageContainsJoinedWord(left, right, in: pageText),
                   let joined = pageSpelling(
                    of: stripTrailingHyphen(left).filter(\.isLetter)
                        + right.filter(\.isLetter),
                    in: pageText
                   ) {
                    result.append(joined)
                    index += 2
                    continue
                }
            }
            result.append(phrases[index])
            index += 1
        }
        return result
    }

    private static func resolvePhrase(_ phrase: String, in pageText: String) -> String {
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        if let recovered = recoverWrapFragment(trimmed, in: pageText) {
            return recovered
        }
        if let match = pageSpelling(of: trimmed, in: pageText) { return match }

        let compact = trimmed.replacingOccurrences(
            of: #"[\s\-‐‑–]+"#,
            with: "",
            options: .regularExpression
        )
        if compact.count >= 4, let match = pageSpelling(of: compact, in: pageText) {
            return match
        }
        return trimmed
            .replacingOccurrences(of: #"([A-Za-z])-\s+"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
    }

    /// Leftover wrap half (`pensed`) → full page word (`dispensed`) when unique.
    private static func recoverWrapFragment(_ fragment: String, in pageText: String) -> String? {
        let letters = fragment.filter(\.isLetter)
        guard letters.count >= 4 else { return nil }

        let needle = letters.lowercased()
        let candidates = latinWords(in: pageText).filter { word in
            let lower = word.lowercased()
            let extra = lower.count - needle.count
            guard extra >= 2, extra <= 6 else { return false }
            return lower.hasSuffix(needle)
        }
        let uniqueKeys = Set(candidates.map { $0.lowercased() })
        guard uniqueKeys.count == 1,
              let key = uniqueKeys.first,
              let match = candidates.first(where: { $0.lowercased() == key }) else {
            return nil
        }
        // A real standalone word stays as-is (`thrift`). Only upgrade shards
        // that are not themselves a whole word on the unwrapped page.
        if pageSpelling(of: letters, in: pageText) != nil { return nil }
        return match
    }

    private static func latinWords(in pageText: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "[A-Za-z]{4,}") else { return [] }
        let nsRange = NSRange(pageText.startIndex..., in: pageText)
        return regex.matches(in: pageText, range: nsRange).compactMap { match in
            guard let range = Range(match.range, in: pageText) else { return nil }
            return String(pageText[range])
        }
    }

    private static func unwrappedPage(_ text: String) -> String {
        var value = text.replacingOccurrences(
            of: #"([A-Za-z])-\s+"#,
            with: "$1",
            options: .regularExpression
        )
        // "dis-pensed" (no space) is still a book wrap, not "well-known".
        value = value.replacingOccurrences(
            of: #"([A-Za-z]{2,5})-([a-z]{4,})"#,
            with: "$1$2",
            options: .regularExpression
        )
        return value
    }

    private static func pageSpelling(of word: String, in pageText: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: word)
        let pattern = "\\b\(escaped)\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        let nsRange = NSRange(pageText.startIndex..., in: pageText)
        guard let match = regex.firstMatch(in: pageText, range: nsRange),
              let range = Range(match.range, in: pageText) else {
            return nil
        }
        return String(pageText[range])
    }

    private static func isHyphenOnly(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.allSatisfy(isHyphen)
    }

    private static func stripTrailingHyphen(_ text: String) -> String {
        var value = text
        while let last = value.last, isHyphen(last) || last.isWhitespace {
            value.removeLast()
        }
        return value
    }

    private static func tokenEndsWithHyphen(_ text: String) -> Bool {
        guard let last = text.last else { return false }
        return isHyphen(last)
    }

    private static func isHyphen(_ character: Character) -> Bool {
        character == "-" || character == "‐" || character == "‑" || character == "–"
    }

    private static func isMostlyCJK(_ text: String) -> Bool {
        let scalars = text.unicodeScalars
        guard !scalars.isEmpty else { return false }
        let cjk = scalars.filter { scalar in
            (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value)
        }.count
        return Double(cjk) / Double(scalars.count) >= 0.6
    }
}

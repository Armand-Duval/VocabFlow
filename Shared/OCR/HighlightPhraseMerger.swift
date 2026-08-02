import Foundation

/// Merge OCR tokens under highlighter ink into vocabulary phrases.
///
/// Book highlighters often break a single idiom across lines and leave short
/// glue words (`a` / `of`) under-inked. We keep one span whenever hard hits are
/// connected by only glue / weak-ink tokens (including wraps).
enum HighlightPhraseMerger {
    struct Token: Equatable {
        let text: String
        let lineIndex: Int
        let coverage: Double
        let minX: Double
        let maxX: Double

        init(
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

    static let hitThreshold = 0.40
    /// Soft ink — enough to sit inside a highlighter stroke.
    static let weakThreshold = 0.12

    private static let glueWords: Set<String> = [
        "a", "an", "the", "of", "to", "in", "on", "at", "for", "and", "or", "but",
        "as", "by", "with", "from", "into", "over", "onto", "upon", "per", "via",
        "is", "are", "was", "were", "be", "been", "am", "do", "does", "did",
        "not", "no", "so", "if", "than", "then", "that", "this", "these", "those",
        "it", "its", "his", "her", "their", "our", "my", "your",
    ]

    static func merge(tokens: [Token], hitThreshold: Double = hitThreshold) -> [String] {
        guard !tokens.isEmpty else { return [] }

        // Never seed on glue — yellow bleed often paints "of"/"my" more than the headword.
        let hard: [Bool] = tokens.map { token in
            let key = normalizedGlueKey(token.text)
            if glueWords.contains(key) { return false }
            if token.coverage >= hitThreshold { return true }
            // Mid ink on a real content word (e.g. clincher ~0.22) still counts as a marker.
            if token.coverage >= 0.22,
               token.text.count >= 4,
               !glueWords.contains(key) {
                return true
            }
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
            maxSpan: 8
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
                    include: include
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
        maxSpan: Int
    ) {
        let hardIndices = hard.indices.filter { hard[$0] }
        guard hardIndices.count >= 2 else { return }

        for pair in zip(hardIndices, hardIndices.dropFirst()) {
            let left = pair.0
            let right = pair.1
            let gap = right - left
            guard gap > 1, gap <= maxSpan else { continue }
            guard canJoinHardHits(left: left, right: right, tokens: tokens) else { continue }

            for i in (left + 1)..<right {
                include[i] = true
            }
        }
    }

    private static func canJoinHardHits(
        left: Int,
        right: Int,
        tokens: [Token]
    ) -> Bool {
        let leftToken = tokens[left]
        let rightToken = tokens[right]

        let lineDelta = rightToken.lineIndex - leftToken.lineIndex
        guard lineDelta == 0 || lineDelta == 1 else { return false }

        if lineDelta == 1 {
            // Wrapped highlight: continuation should start toward the left margin.
            guard isWrapContinuation(from: leftToken, to: rightToken) else { return false }
        }

        for i in (left + 1)..<right {
            guard isGapToken(tokens[i]) else { return false }
        }
        return true
    }

    /// Adjacent included tokens that are both hard hits on different lines, with
    /// no gap fill between them, are separate markers unless this looks like a wrap.
    private static func shouldSplitRun(
        previous: Int,
        current: Int,
        tokens: [Token],
        hard: [Bool],
        include: [Bool]
    ) -> Bool {
        guard include[previous], include[current] else { return false }
        // Soft/gap tokens between hard hits were intentionally filled — keep them.
        if !hard[previous] || !hard[current] { return false }
        let a = tokens[previous]
        let b = tokens[current]
        if a.lineIndex == b.lineIndex { return false }
        return !isWrapContinuation(from: a, to: b)
    }

    private static func isWrapContinuation(from a: Token, to b: Token) -> Bool {
        // Require the previous token to sit near the right margin so mid-line
        // markers on consecutive lines (e.g. record → remarkable) stay separate.
        b.lineIndex == a.lineIndex + 1
            && b.minX <= 0.50
            && a.maxX >= 0.68
    }

    private static func isGapToken(_ token: Token) -> Bool {
        if token.coverage >= weakThreshold { return true }
        let key = normalizedGlueKey(token.text)
        if glueWords.contains(key) { return true }
        return key.count <= 3
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
        let texts = parts.map(\.text)
        guard !texts.isEmpty else { return }

        let joined: String
        if texts.allSatisfy(isMostlyCJK) {
            joined = texts.joined()
        } else {
            joined = texts.joined(separator: " ")
        }
        let trimmed = joined.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 1, trimmed.count <= 72 else { return }
        phrases.append(trimmed)
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

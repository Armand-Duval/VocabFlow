import Foundation

/// Normalizes poetry line breaks for storage and display (AI sometimes emits " / " or "，/").
public enum LiteraryTextFormatting {
    public static func display(_ text: String) -> String {
        var result = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        // Punctuation + optional spaces + slash + optional spaces → newline after punctuation.
        result = replaceRegex(
            in: result,
            pattern: #"([，,；;：:])\s*/\s*"#,
            template: "$1\n"
        )

        // Remaining slash breaks with surrounding whitespace.
        result = replaceRegex(
            in: result,
            pattern: #"\s+/+\s+"#,
            template: "\n"
        )

        return result
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Reject AI output that uses symbols the reader should never see in a literary quote.
    public static func containsInvalidMarkers(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if trimmed.contains("/") {
            return true
        }
        if trimmed.contains("```") || trimmed.contains("**") || trimmed.contains("__") || trimmed.contains("<") {
            return true
        }
        if trimmed.contains("\\n") || trimmed.contains("|") {
            return true
        }
        return false
    }

    /// Split source for quote vs translation attribution blocks.
    public static func sourceParts(source: String?, sentence: String) -> (quote: String?, translation: String?) {
        guard let raw = source?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return (nil, nil)
        }

        if raw.contains(" | ") {
            let parts = raw
                .components(separatedBy: " | ")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if parts.count >= 2 {
                let firstIsLatin = latinLetterCount(parts[0]) > hanCount(parts[0])
                let secondIsLatin = latinLetterCount(parts[1]) > hanCount(parts[1])
                if firstIsLatin, !secondIsLatin {
                    return (parts[0], parts[1])
                }
                if secondIsLatin, !firstIsLatin {
                    return (parts[1], parts[0])
                }
                return (parts[0], parts[1])
            }
        }

        let sentenceIsEnglish = latinLetterCount(sentence) >= 4 && latinLetterCount(sentence) > hanCount(sentence)
        let sourceIsLatin = latinLetterCount(raw) > hanCount(raw)
        if sentenceIsEnglish {
            if sourceIsLatin {
                return (raw, nil)
            }
            return (nil, raw)
        }
        return (nil, raw)
    }

    public static func latinLetterCount(_ text: String) -> Int {
        text.unicodeScalars.filter { CharacterSet.letters.contains($0) && $0.isASCII }.count
    }

    public static func hanCount(_ text: String) -> Int {
        text.unicodeScalars.filter { (0x4E00...0x9FFF).contains($0.value) }.count
    }

    private static func replaceRegex(in text: String, pattern: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}

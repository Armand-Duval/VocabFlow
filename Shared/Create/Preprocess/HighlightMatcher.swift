import Foundation
#if canImport(UIKit)
import UIKit
#endif

public enum HighlightMatchStyle {
    /// Prefer whole-phrase / token boundaries — study cards (avoids marking every “a”).
    case wordBounded
    /// Raw substring — search results.
    case substring
}

public enum HighlightMatcher {
    /// Ranges in `text` that should be highlighted for `terms` (longer first).
    public static func ranges(
        of terms: [String],
        in text: String,
        style: HighlightMatchStyle
    ) -> [Range<String.Index>] {
        let cleaned = terms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty, !text.isEmpty else { return [] }

        var occupied = IndexSet()
        var result: [Range<String.Index>] = []
        let nsText = text as NSString
        let utf16Length = nsText.length

        for term in cleaned.sorted(by: { $0.count > $1.count }) {
            for nsRange in nsRanges(of: term, in: text, style: style) {
                guard nsRange.location != NSNotFound,
                      nsRange.location + nsRange.length <= utf16Length else { continue }
                let indices = IndexSet(integersIn: nsRange.location..<(nsRange.location + nsRange.length))
                if !occupied.intersection(indices).isEmpty { continue }
                guard let range = Range(nsRange, in: text) else { continue }
                occupied.formUnion(indices)
                result.append(range)
            }
        }
        return result
    }

    #if canImport(UIKit)
    public static func attributedString(
        text: String,
        terms: [String],
        style: HighlightMatchStyle,
        font: UIFont,
        textColor: UIColor,
        highlightBackground: UIColor,
        highlightForeground: UIColor?,
        semibold: Bool
    ) -> NSAttributedString {
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: textColor
            ]
        )
        let highlightFont: UIFont = {
            if semibold,
               let descriptor = font.fontDescriptor.withSymbolicTraits(.traitBold) {
                return UIFont(descriptor: descriptor, size: font.pointSize)
            }
            return font
        }()

        for range in ranges(of: terms, in: text, style: style) {
            let nsRange = NSRange(range, in: text)
            attributed.addAttribute(.backgroundColor, value: highlightBackground, range: nsRange)
            if semibold {
                attributed.addAttribute(.font, value: highlightFont, range: nsRange)
            }
            if let highlightForeground {
                attributed.addAttribute(.foregroundColor, value: highlightForeground, range: nsRange)
            }
        }
        return attributed
    }
    #endif

    private static func nsRanges(
        of term: String,
        in text: String,
        style: HighlightMatchStyle
    ) -> [NSRange] {
        switch style {
        case .substring:
            return substringRanges(of: term, in: text)
        case .wordBounded:
            if let regexRanges = boundedRegexRanges(of: term, in: text) {
                return regexRanges
            }
            return substringRanges(of: term, in: text)
        }
    }

    private static func substringRanges(of term: String, in text: String) -> [NSRange] {
        let ns = text as NSString
        var search = NSRange(location: 0, length: ns.length)
        var found: [NSRange] = []
        while search.length > 0 {
            let hit = ns.range(of: term, options: [.caseInsensitive], range: search)
            guard hit.location != NSNotFound else { break }
            found.append(hit)
            let next = hit.location + max(hit.length, 1)
            search = NSRange(location: next, length: max(0, ns.length - next))
        }
        return found
    }

    private static func boundedRegexRanges(of term: String, in text: String) -> [NSRange]? {
        let parts = term
            .split { $0.isWhitespace || $0.isNewline }
            .map { NSRegularExpression.escapedPattern(for: String($0)) }
        guard !parts.isEmpty else { return nil }
        let flexible = parts.joined(separator: "\\s+")
        // Don't match inside larger Latin/digit tokens (fixes “a” in “and”).
        let pattern = "(?<![\\p{L}\\p{N}_])\(flexible)(?![\\p{L}\\p{N}_])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        return regex.matches(in: text, options: [], range: full).map(\.range)
    }
}

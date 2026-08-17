import Foundation

enum CardType: String, Codable, CaseIterable {
    case cloze
    case definition
    case appreciation

    var displayName: String {
        switch self {
        case .cloze: L10n.cardTypeCloze
        case .definition: L10n.cardTypeDefinition
        case .appreciation: L10n.cardTypeAppreciation
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
    /// Why this word here; near-synonym / alternative contrast.
    var usageNote: String? = nil
    /// Root / affix / morphology when helpful.
    var etymology: String? = nil
    /// Near-synonyms joined for display / edit.
    var synonyms: String? = nil
    /// Antonyms / contrasts joined for display / edit.
    var antonyms: String? = nil
    /// Scene-tagged model sentences (multiline).
    var paraphrases: String? = nil
    /// Book / article / author when AI (or page header) can identify it.
    var sourceAttribution: String?
    /// App Group relative path to the source screenshot / photo, if any.
    var sourceImagePath: String? = nil
    var isSelected: Bool = true
    /// AI-recommended primary card for this word (shown in compact mode).
    var isRecommended: Bool = false

    var studyContent: CardStudyContent {
        CardStudyContent(
            word: word,
            phonetic: phonetic,
            sentence: sentence,
            cardType: cardType,
            front: front,
            back: back,
            contextNote: contextNote,
            usageNote: usageNote,
            etymology: etymology,
            synonyms: synonyms,
            antonyms: antonyms,
            paraphrases: paraphrases,
            sourceAttribution: sourceAttribution,
            sourceImagePath: sourceImagePath
        )
    }
}

/// Display snapshot shared by review and create-preview.
struct CardStudyContent: Equatable {
    var word: String
    var phonetic: String?
    var sentence: String
    var cardType: CardType
    var front: String
    var back: String
    var contextNote: String?
    var usageNote: String?
    var etymology: String?
    var synonyms: String?
    var antonyms: String?
    var paraphrases: String?
    var sourceAttribution: String?
    var sourceImagePath: String?
    var highlightText: String? = nil

    var displayHighlight: String {
        let custom = highlightText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !custom.isEmpty { return custom }
        return word
    }

    var displayFront: String {
        CardContentFormatter.displayFront(
            front: front,
            sentence: sentence,
            word: word,
            cardType: cardType
        )
    }

    var displayBack: String {
        CardContentFormatter.displayBack(back: back, contextNote: contextNote)
    }
}

struct CardParaphrase: Equatable, Identifiable {
    var id: String { "\(scene)|\(sentence)" }
    var scene: String
    var sentence: String
    var note: String?
}

enum CardReplaceReason: String, CaseIterable, Identifiable {
    case wrongSense
    case tooHard
    case tooEasy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wrongSense: L10n.createPreviewReplaceWrongSense
        case .tooHard: L10n.createPreviewReplaceTooHard
        case .tooEasy: L10n.createPreviewReplaceTooEasy
        }
    }

    var promptInstruction: String {
        switch self {
        case .wrongSense:
            "上一张卡的义项不对。请按原句里真正的意思重做，不要沿用刚才的释义。"
        case .tooHard:
            "上一张卡太难、信息太满。请更短、更贴近本句，降低难度。"
        case .tooEasy:
            "上一张卡太浅，几乎不用想。请抓住本句里更值得记的一点，让正面需要真正回忆。"
        }
    }
}

enum CardGenerationMode: String, CaseIterable, Identifiable {
    case compact
    case full

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: L10n.createCardModeCompact
        case .full: L10n.createCardModeFull
        }
    }

    var detail: String {
        switch self {
        case .compact: L10n.createCardModeCompactDetail
        case .full: L10n.createCardModeFullDetail
        }
    }
}

enum CardGenerationPreferences {
    private static let modeKey = "cardGeneration.mode.v1"

    static var mode: CardGenerationMode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: modeKey),
                  let value = CardGenerationMode(rawValue: raw) else {
                return .compact
            }
            return value
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: modeKey)
        }
    }
}

enum CardContentFormatter {
    /// Join synonym / antonym tokens for storage (`a · b · c`).
    static func joinRelatedWords(_ words: [String]) -> String? {
        let cleaned = words
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return nil }
        var seen = Set<String>()
        var unique: [String] = []
        for word in cleaned {
            let key = word.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            unique.append(word)
        }
        return unique.isEmpty ? nil : unique.joined(separator: " · ")
    }

    static func splitRelatedWords(_ text: String?) -> [String] {
        let raw = trimmed(text)
        guard !raw.isEmpty else { return [] }
        let separators = CharacterSet(charactersIn: "·•、,，;/|｜\n")
        return raw
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func encodeParaphrases(_ items: [CardParaphrase]) -> String? {
        let blocks = items.compactMap { item -> String? in
            let scene = item.scene.trimmingCharacters(in: .whitespacesAndNewlines)
            let sentence = item.sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sentence.isEmpty else { return nil }
            var lines: [String] = []
            if scene.isEmpty {
                lines.append(sentence)
            } else {
                lines.append("【\(scene)】\(sentence)")
            }
            if let note = item.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                lines.append("（\(note)）")
            }
            return lines.joined(separator: "\n")
        }
        guard !blocks.isEmpty else { return nil }
        return blocks.joined(separator: "\n\n")
    }

    static func decodeParaphrases(_ text: String?) -> [CardParaphrase] {
        let raw = trimmed(text)
        guard !raw.isEmpty else { return [] }

        let blocks = raw
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return blocks.compactMap { block in
            let lines = block
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard let first = lines.first else { return nil }

            var scene = ""
            var sentence = first
            if first.hasPrefix("【"),
               let close = first.firstIndex(of: "】") {
                scene = String(first[first.index(after: first.startIndex)..<close])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                sentence = String(first[first.index(after: close)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }

            var note: String?
            if lines.count >= 2 {
                let second = lines[1]
                if second.hasPrefix("（"), second.hasSuffix("）"), second.count >= 3 {
                    note = String(second.dropFirst().dropLast())
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                } else if second.hasPrefix("("), second.hasSuffix(")"), second.count >= 3 {
                    note = String(second.dropFirst().dropLast())
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    note = second
                }
            }

            guard !sentence.isEmpty else { return nil }
            let tip = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return CardParaphrase(
                scene: scene,
                sentence: sentence,
                note: tip.isEmpty ? nil : tip
            )
        }
    }

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

    /// True when the card has a real example sentence, not just the headword.
    static func hasExamplePrompt(sentence: String, word: String) -> Bool {
        let trimmedSentence = trimmed(sentence)
        guard !trimmedSentence.isEmpty else { return false }
        return !isWordOnlyFront(trimmedSentence, word: word)
    }

    static func sentenceTranslation(_ contextNote: String?) -> String? {
        let value = stripHighlightMarkers(trimmed(contextNote))
        guard !value.isEmpty else { return nil }
        if isNonTranslationNote(value) { return nil }
        return value
    }

    /// POS tags and pack labels were once written into `contextNote`; they are not 译文.
    private static func isNonTranslationNote(_ text: String) -> Bool {
        let folded = text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let partOfSpeech: Set<String> = [
            "noun", "verb", "adjective", "adverb", "pronoun", "preposition",
            "conjunction", "interjection", "determiner", "article",
            "n", "v", "adj", "adv", "prep", "conj"
        ]
        if partOfSpeech.contains(folded) { return true }
        if folded == "ngsl 1.2" || folded == "nawl 1.2" { return true }
        return false
    }

    /// Generic type name used when AI never wrote a real theme.
    static func isPlaceholderAppreciationTheme(_ theme: String) -> Bool {
        let value = trimmed(theme)
        if value.isEmpty { return true }
        if value.caseInsensitiveCompare(L10n.cardTypeAppreciation) == .orderedSame { return true }
        return ["赏析", "appreciation"].contains { $0.caseInsensitiveCompare(value) == .orderedSame }
    }

    static func isHollowAppreciation(_ draft: GeneratedCardDraft) -> Bool {
        isHollowAppreciation(
            theme: draft.back,
            translation: draft.contextNote,
            appreciation: draft.usageNote
        )
    }

    static func isHollowAppreciation(theme: String, translation: String?, appreciation: String?) -> Bool {
        let note = trimmed(appreciation)
        let trans = sentenceTranslation(translation) ?? ""
        return note.isEmpty && trans.isEmpty
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

    /// First 【…】 / 「…」 span in a context note, if any.
    static func primaryHighlightTerm(from contextNote: String?) -> String {
        extractMarkedTerms(from: trimmed(contextNote)).first ?? ""
    }

    /// Rebuild translation with a single 【term】 marker (replaces any prior markers).
    static func applyHighlightMarker(to translation: String, term: String) -> String {
        let plain = stripHighlightMarkers(translation).trimmingCharacters(in: .whitespacesAndNewlines)
        let gloss = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plain.isEmpty else { return "" }
        guard !gloss.isEmpty else { return plain }
        guard let range = plain.range(of: gloss) else { return plain }
        return plain.replacingCharacters(in: range, with: "【\(gloss)】")
    }

    static func highlightTermIsPresent(in translation: String, term: String) -> Bool {
        let plain = stripHighlightMarkers(translation)
        let gloss = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !gloss.isEmpty else { return true }
        return plain.contains(gloss)
    }

    /// Ensure sentence translation has a short 【…】 mark for the target word.
    /// Prefer AI markers; otherwise use explicit `highlight` / sense gloss fallback.
    static func ensureTranslationHighlight(
        contextNote: String?,
        sense: String,
        explicitHighlight: String? = nil
    ) -> String? {
        let raw = trimmed(contextNote)
        guard !raw.isEmpty else { return nil }

        var note = normalizeAlternateHighlightMarkers(raw)
        let plain = stripHighlightMarkers(note)
        guard !plain.isEmpty else { return nil }

        let marked = extractMarkedTerms(from: note)
        if let first = marked.first {
            // AI sometimes wraps a whole clause; shrink when a short gloss fits inside.
            if first.count > 10,
               let shorter = preferredShortGloss(
                plain: first,
                sense: sense,
                explicitHighlight: explicitHighlight
               ),
               first.contains(shorter) {
                return applyHighlightMarker(to: plain, term: shorter)
            }
            if marked.count == 1 {
                return note.contains("【") ? note : applyHighlightMarker(to: plain, term: first)
            }
            // Multiple marks → keep only the shortest reasonable one.
            if let best = marked
                .filter({ $0.count <= 12 })
                .min(by: { $0.count < $1.count }) {
                return applyHighlightMarker(to: plain, term: best)
            }
            return applyHighlightMarker(to: plain, term: first)
        }

        if let gloss = preferredShortGloss(
            plain: plain,
            sense: sense,
            explicitHighlight: explicitHighlight
        ) {
            return applyHighlightMarker(to: plain, term: gloss)
        }

        return plain
    }

    /// Convert common wrong wrappers into 【】 before extraction.
    private static func normalizeAlternateHighlightMarkers(_ text: String) -> String {
        var result = text
        let patterns = [
            #"\[([^\[\]]{1,12})\]"#,
            #"［([^］]{1,12})］"#,
            #"\*\*([^*]{1,12})\*\*"#,
            #"__([^_]{1,12})__"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: "【$1】"
            )
        }
        return result
    }

    private static func preferredShortGloss(
        plain: String,
        sense: String,
        explicitHighlight: String?
    ) -> String? {
        var candidates: [String] = []
        let explicit = trimmed(explicitHighlight)
        if !explicit.isEmpty {
            candidates.append(explicit)
        }
        candidates.append(contentsOf: glossCandidates(from: sense))

        let unique = uniqueTerms(candidates)
        // Prefer shorter matches that actually appear in the translation.
        return unique
            .filter { $0.count <= 10 && plain.contains($0) }
            .min(by: { $0.count < $1.count })
            ?? unique.first { plain.contains($0) }
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
        case .appreciation:
            if !trimmedSentence.isEmpty {
                return trimmedSentence
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

    /// Build a cloze front by blanking the target word/phrase in the source sentence.
    static func makeClozeFront(sentence: String, word: String) -> String {
        let trimmedSentence = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSentence.isEmpty, !trimmedWord.isEmpty else { return trimmedSentence }

        if let range = trimmedSentence.range(of: trimmedWord, options: .caseInsensitive) {
            return trimmedSentence.replacingCharacters(in: range, with: "______")
        }
        return trimmedSentence
    }

    /// Derive the alternate card type from a primary draft (compact mode optional sibling).
    static func siblingDraft(from primary: GeneratedCardDraft) -> GeneratedCardDraft {
        let siblingType: CardType = primary.cardType == .cloze ? .definition : .cloze
        let siblingFront: String
        if siblingType == .cloze {
            siblingFront = makeClozeFront(sentence: primary.sentence, word: primary.word)
        } else {
            siblingFront = primary.sentence
        }
        return GeneratedCardDraft(
            word: primary.word,
            phonetic: primary.phonetic,
            sentence: primary.sentence,
            cardType: siblingType,
            front: normalizedFront(
                front: siblingFront,
                sentence: primary.sentence,
                word: primary.word,
                cardType: siblingType
            ),
            back: primary.back,
            contextNote: primary.contextNote,
            usageNote: primary.usageNote,
            etymology: primary.etymology,
            synonyms: primary.synonyms,
            antonyms: primary.antonyms,
            paraphrases: primary.paraphrases,
            sourceAttribution: primary.sourceAttribution,
            sourceImagePath: primary.sourceImagePath,
            isSelected: false,
            isRecommended: false
        )
    }

    /// Append unselected sibling cards so preview can opt in without another AI call.
    static func expandOptionalSiblings(_ drafts: [GeneratedCardDraft]) -> [GeneratedCardDraft] {
        var result: [GeneratedCardDraft] = []
        var existing = Set<String>()

        for draft in drafts {
            let key = draftSelectionKey(word: draft.word, cardType: draft.cardType)
            result.append(draft)
            existing.insert(key)

            let sibling = siblingDraft(from: draft)
            let siblingKey = draftSelectionKey(word: sibling.word, cardType: sibling.cardType)
            guard !existing.contains(siblingKey) else { continue }
            result.append(sibling)
            existing.insert(siblingKey)
        }
        return result
    }

    static func draftSelectionKey(word: String, cardType: CardType) -> String {
        "\(word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())|\(cardType.rawValue)"
    }

    /// Library / card list title for sentence-level appreciation cards.
    static func appreciationWordLabel(source: String?, sentence: String) -> String {
        let trimmedSource = source?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedSource.isEmpty {
            let primary = trimmedSource
                .components(separatedBy: CharacterSet(charactersIn: "·•|｜,"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { !$0.isEmpty }) ?? trimmedSource
            if primary.count <= 28 {
                return primary
            }
            return String(primary.prefix(28)) + "…"
        }

        let trimmedSentence = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSentence.count <= 24 {
            return trimmedSentence
        }
        return String(trimmedSentence.prefix(24)) + "…"
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

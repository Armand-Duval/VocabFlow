import Foundation

extension CardType {
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
    /// AI-recommended primary card for this word.
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

extension GeneratedCardDraft {
    init(from content: CardStudyContent, isSelected: Bool = true, isRecommended: Bool = true) {
        self.init(
            word: content.word,
            phonetic: content.phonetic,
            sentence: content.sentence,
            cardType: content.cardType,
            front: content.front,
            back: content.back,
            contextNote: content.contextNote,
            usageNote: content.usageNote,
            etymology: content.etymology,
            synonyms: content.synonyms,
            antonyms: content.antonyms,
            paraphrases: content.paraphrases,
            sourceAttribution: content.sourceAttribution,
            sourceImagePath: content.sourceImagePath,
            isSelected: isSelected,
            isRecommended: isRecommended
        )
    }
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

extension CardStudyContent {
    var localizedDisplayBack: String {
        displayBack(translationLabel: L10n.cardSentenceTranslation)
    }
}

extension CardContentFormatter {
    static func isHollowAppreciation(_ draft: GeneratedCardDraft) -> Bool {
        isHollowAppreciation(
            theme: draft.back,
            translation: draft.contextNote,
            appreciation: draft.usageNote
        )
    }

    /// Derive the other exam type from the AI primary.
    /// Shares meaning, usage, and extras; only the front is reformatted.
    /// Selected by default, but not marked as the recommended card.
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
            isSelected: true,
            isRecommended: false
        )
    }

    /// Append the sibling exam type so preview can save both without another AI call.
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
}

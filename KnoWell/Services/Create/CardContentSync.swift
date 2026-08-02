import Foundation

/// Single place that maps generator output → stored card **content** fields.
/// Migration and new saves both go through here, so new AI fields only need one apply path
/// (plus the generator prompt / `GeneratedCardDraft` / `FlashCard` model).
enum CardContentSync {
    /// Overwrite learnable content from the latest generator rules. Keeps id / deck / SRS.
    @MainActor
    static func applyGeneratedContent(_ draft: GeneratedCardDraft, to card: FlashCard) {
        let word = draft.word.trimmingCharacters(in: .whitespacesAndNewlines)
        if !word.isEmpty {
            card.word = word
        }

        let sentence = draft.sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sentence.isEmpty {
            card.sentence = sentence
        }

        card.cardType = draft.cardType
        card.front = CardContentFormatter.normalizedFront(
            front: draft.front,
            sentence: card.sentence,
            word: card.word,
            cardType: card.cardType
        )
        card.back = draft.back.trimmingCharacters(in: .whitespacesAndNewlines)

        let note = draft.contextNote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        card.contextNote = note.isEmpty ? nil : note

        if let phonetic = draft.phonetic?.trimmingCharacters(in: .whitespacesAndNewlines),
           !phonetic.isEmpty {
            card.phonetic = phonetic
        }

        if let source = draft.sourceAttribution?.trimmingCharacters(in: .whitespacesAndNewlines),
           !source.isEmpty {
            card.sourceAttribution = source
        }
    }

    @MainActor
    static func makeCard(from draft: GeneratedCardDraft, deck: Deck) -> FlashCard {
        let card = FlashCard(
            word: draft.word,
            sentence: draft.sentence,
            cardType: draft.cardType,
            front: draft.front,
            back: draft.back,
            deck: deck
        )
        applyGeneratedContent(draft, to: card)
        return card
    }
}

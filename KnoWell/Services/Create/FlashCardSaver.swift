import Foundation
import SwiftData

struct FlashCardSaveResult {
    let savedCount: Int
    let skippedDuplicateCount: Int
    var savedCards: [FlashCard] = []

    var didSaveAny: Bool { savedCount > 0 }
    var skippedAll: Bool { savedCount == 0 && skippedDuplicateCount > 0 }
}

enum FlashCardSaver {
    @MainActor
    @discardableResult
    static func save(drafts: [GeneratedCardDraft], to context: ModelContext, deck: Deck) -> FlashCardSaveResult {
        let selected = drafts.filter(\.isSelected)
        guard !selected.isEmpty else {
            return FlashCardSaveResult(savedCount: 0, skippedDuplicateCount: 0)
        }

        let existing = FlashCardDeduper.cards(in: deck, context: context)
        var savedKeys = Set<String>()
        var savedCards: [FlashCard] = []
        var skippedDuplicateCount = 0

        for draft in selected {
            let word = draft.word.trimmingCharacters(in: .whitespacesAndNewlines)
            let sentence = draft.sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = duplicateKey(word: word, sentence: sentence, cardType: draft.cardType)

            let existsInDeck = existing.contains {
                FlashCardDeduper.matches($0, word: word, sentence: sentence, cardType: draft.cardType)
            }
            if existsInDeck || savedKeys.contains(key) {
                skippedDuplicateCount += 1
                continue
            }

            let card = CardContentSync.makeCard(from: draft, deck: deck)
            context.insert(card)
            savedKeys.insert(key)
            savedCards.append(card)
        }

        guard !savedCards.isEmpty else {
            return FlashCardSaveResult(savedCount: 0, skippedDuplicateCount: skippedDuplicateCount)
        }

        do {
            try context.save()
        } catch {
            // SwiftData 通常会自动持久化；显式 save 失败时不阻断流程
        }

        DeckSettings.lastSelectedDeckID = deck.id
        DeckCardCountService.adjust(deck: deck, by: savedCards.count, in: context)
        DeckCardCountService.notifyCatalogChanged()
        SharedDedupeIndex.insert(
            deckID: deck.id,
            pairs: selected.compactMap { draft in
                let word = draft.word.trimmingCharacters(in: .whitespacesAndNewlines)
                let sentence = draft.sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !word.isEmpty, !sentence.isEmpty else { return nil }
                return (word, sentence)
            }
        )
        return FlashCardSaveResult(
            savedCount: savedCards.count,
            skippedDuplicateCount: skippedDuplicateCount,
            savedCards: savedCards
        )
    }

    private static func duplicateKey(word: String, sentence: String, cardType: CardType) -> String {
        [
            FlashCardDeduper.normalizedWord(word),
            FlashCardDeduper.normalizedSentence(sentence),
            cardType.rawValue
        ].joined(separator: "\u{1f}")
    }
}

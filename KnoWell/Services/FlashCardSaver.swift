import Foundation
import SwiftData

enum FlashCardSaver {
    @MainActor
    @discardableResult
    static func save(drafts: [GeneratedCardDraft], to context: ModelContext, deck: Deck) -> Int {
        let selected = drafts.filter(\.isSelected)
        guard !selected.isEmpty else { return 0 }

        for draft in selected {
            let card = FlashCard(
                word: draft.word,
                sentence: draft.sentence,
                cardType: draft.cardType,
                front: draft.front,
                back: CardContentFormatter.mergedBack(back: draft.back, contextNote: draft.contextNote),
                contextNote: nil,
                phonetic: draft.phonetic,
                deck: deck
            )
            context.insert(card)
        }

        do {
            try context.save()
        } catch {
            // SwiftData 通常会自动持久化；显式 save 失败时不阻断流程
        }

        DeckSettings.lastSelectedDeckID = deck.id
        DeckCardCountService.adjust(deck: deck, by: selected.count, in: context)
        DeckCardCountService.notifyCatalogChanged()
        return selected.count
    }
}

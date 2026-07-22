import Foundation
import SwiftData

enum FlashCardSaver {
    @MainActor
    @discardableResult
    static func save(drafts: [GeneratedCardDraft], to context: ModelContext) -> Int {
        let selected = drafts.filter(\.isSelected)
        guard !selected.isEmpty else { return 0 }

        for draft in selected {
            let card = FlashCard(
                word: draft.word,
                sentence: draft.sentence,
                cardType: draft.cardType,
                front: draft.front,
                back: CardContentFormatter.mergedBack(back: draft.back, contextNote: draft.contextNote),
                contextNote: nil
            )
            context.insert(card)
        }

        do {
            try context.save()
        } catch {
            // SwiftData 通常会自动持久化；显式 save 失败时不阻断流程
        }

        return selected.count
    }
}

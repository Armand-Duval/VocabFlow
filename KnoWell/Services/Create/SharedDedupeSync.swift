import Foundation
import SwiftData

enum SharedDedupeSync {
    /// Rebuild the App Group dedupe index from SwiftData (Share extension can read it).
    @MainActor
    static func rebuild(in context: ModelContext) {
        let descriptor = FetchDescriptor<FlashCard>()
        let cards = (try? context.fetch(descriptor)) ?? []
        var keys = Set<String>()
        for card in cards {
            guard let deckID = card.deck?.id,
                  let key = SharedDedupeIndex.key(
                    deckID: deckID,
                    word: card.word,
                    sentence: card.sentence
                  ) else {
                continue
            }
            keys.insert(key)
        }
        SharedDedupeIndex.replaceAll(keys: keys)
    }
}

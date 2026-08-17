import Foundation
import SwiftData

enum DeckCardCountService {
    private static var cachedDueCounts: [UUID: Int] = [:]

    static func dueCount(for deckID: UUID) -> Int {
        cachedDueCounts[deckID, default: 0]
    }

    @MainActor
    static func adjust(deck: Deck?, by delta: Int, in context: ModelContext, save: Bool = true) {
        guard let deck, delta != 0 else { return }
        deck.cachedCardCount = max(0, deck.cachedCardCount + delta)
        if save {
            try? context.save()
        }
    }

    /// Move cards to `target` and keep `cachedCardCount` in sync. Returns how many cards changed decks.
    @MainActor
    static func moveCards(_ cards: [FlashCard], to target: Deck, in context: ModelContext) -> Int {
        var deltas: [UUID: Int] = [:]
        var decksByID: [UUID: Deck] = [:]
        var moved = 0

        for card in cards {
            let source = card.deck
            if source?.id == target.id { continue }
            if let source {
                deltas[source.id, default: 0] -= 1
                decksByID[source.id] = source
            }
            deltas[target.id, default: 0] += 1
            decksByID[target.id] = target
            card.deck = target
            moved += 1
        }

        for (id, delta) in deltas where delta != 0 {
            if let deck = decksByID[id] {
                deck.cachedCardCount = max(0, deck.cachedCardCount + delta)
            }
        }
        try? context.save()
        return moved
    }

    @MainActor
    static func setCount(deck: Deck, to count: Int, in context: ModelContext) {
        deck.cachedCardCount = max(0, count)
        try? context.save()
    }

    @MainActor
    static func recountAll(in context: ModelContext) {
        let decks = DeckService.fetchAll(in: context)
        let now = Date.now
        var nextDueCounts: [UUID: Int] = [:]
        nextDueCounts.reserveCapacity(decks.count)

        for deck in decks {
            let id = deck.id
            var totalDescriptor = FetchDescriptor<FlashCard>(
                predicate: #Predicate<FlashCard> { card in
                    card.deck?.id == id
                }
            )
            var dueDescriptor = FetchDescriptor<FlashCard>(
                predicate: #Predicate<FlashCard> { card in
                    card.deck?.id == id
                    && card.isSuspended == false
                    && card.nextReviewDate <= now
                }
            )
            if let total = try? context.fetchCount(totalDescriptor) {
                deck.cachedCardCount = total
            }
            nextDueCounts[id] = (try? context.fetchCount(dueDescriptor)) ?? 0
        }

        cachedDueCounts = nextDueCounts
        try? context.save()
    }

    @MainActor
    static func notifyCatalogChanged() {
        NotificationCenter.default.post(name: .libraryCatalogDidChange, object: nil)
    }

    @MainActor
    static func notifyDataMaintenance() {
        NotificationCenter.default.post(name: .dataMaintenanceDidComplete, object: nil)
        NotificationCenter.default.post(name: .reviewQueueDidChange, object: nil)
        notifyCatalogChanged()
    }
}

typealias ImportProgressHandler = @Sendable (Int, Int) -> Void

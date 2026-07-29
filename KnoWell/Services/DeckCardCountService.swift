import Foundation
import SwiftData

enum DeckCardCountService {
    @MainActor
    static func adjust(deck: Deck?, by delta: Int, in context: ModelContext) {
        guard let deck, delta != 0 else { return }
        deck.cachedCardCount = max(0, deck.cachedCardCount + delta)
        try? context.save()
    }

    @MainActor
    static func setCount(deck: Deck, to count: Int, in context: ModelContext) {
        deck.cachedCardCount = max(0, count)
        try? context.save()
    }

    @MainActor
    static func recountAll(in context: ModelContext) {
        let decks = DeckService.fetchAll(in: context)
        for deck in decks {
            deck.cachedCardCount = deck.cards.count
        }
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

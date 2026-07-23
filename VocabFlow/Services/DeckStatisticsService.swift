import Foundation
import SwiftData

struct DeckStatistics: Sendable {
    let totalCards: Int
    let dueCount: Int
    let newCount: Int
    let learnedCount: Int

    var masteryRate: Double {
        guard totalCards > 0 else { return 0 }
        return Double(learnedCount) / Double(totalCards)
    }
}

enum DeckStatisticsService {
    @MainActor
    static func statistics(for deck: Deck, in context: ModelContext, now: Date = .now) -> DeckStatistics {
        let id = deck.id
        var descriptor = FetchDescriptor<FlashCard>(
            predicate: #Predicate<FlashCard> { $0.deck?.id == id }
        )
        guard let cards = try? context.fetch(descriptor) else {
            return DeckStatistics(totalCards: deck.cachedCardCount, dueCount: 0, newCount: 0, learnedCount: 0)
        }

        var due = 0
        var newCount = 0
        var learned = 0
        for card in cards {
            if ReviewScheduler.isDue(card, now: now) { due += 1 }
            if card.isNewCard { newCount += 1 }
            if card.reviewCount > 0 || card.repetitions > 0 { learned += 1 }
        }

        return DeckStatistics(
            totalCards: cards.count,
            dueCount: due,
            newCount: newCount,
            learnedCount: learned
        )
    }
}

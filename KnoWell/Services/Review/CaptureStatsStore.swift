import Foundation
import SwiftData

/// Today’s capture counts for the review-home stat row.
enum CaptureStatsStore {
    struct Summary: Equatable {
        let cardCount: Int
        let uniqueWords: Int
        let uniqueSentences: Int
    }

    @MainActor
    static func todaySummary(in context: ModelContext, now: Date = .now) -> Summary? {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }

        let descriptor = FetchDescriptor<FlashCard>(
            predicate: #Predicate<FlashCard> { card in
                card.createdAt >= start && card.createdAt < end
            }
        )
        let cards = (try? context.fetch(descriptor)) ?? []
        guard !cards.isEmpty else { return nil }

        var words = Set<String>()
        var sentences = Set<String>()
        for card in cards {
            let word = SharedDedupeIndex.normalizedWord(card.word)
            let sentence = SharedDedupeIndex.normalizedSentence(card.sentence)
            if !word.isEmpty { words.insert(word) }
            if !sentence.isEmpty { sentences.insert(sentence) }
        }

        guard !words.isEmpty || !sentences.isEmpty else { return nil }
        return Summary(cardCount: cards.count, uniqueWords: words.count, uniqueSentences: sentences.count)
    }
}

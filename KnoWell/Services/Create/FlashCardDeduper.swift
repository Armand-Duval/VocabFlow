import Foundation
import SwiftData

/// Deck-scoped uniqueness for create flow: same word + sentence (+ optional card type).
enum FlashCardDeduper {
    static func normalizedWord(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func normalizedSentence(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
    }

    @MainActor
    static func cards(in deck: Deck, context: ModelContext) -> [FlashCard] {
        let deckID = deck.id
        let descriptor = FetchDescriptor<FlashCard>(
            predicate: #Predicate<FlashCard> { card in
                card.deck?.id == deckID
            }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    @MainActor
    static func contains(
        word: String,
        sentence: String,
        in deck: Deck,
        cardType: CardType? = nil,
        context: ModelContext
    ) -> Bool {
        let wordKey = normalizedWord(word)
        let sentenceKey = normalizedSentence(sentence)
        guard !wordKey.isEmpty, !sentenceKey.isEmpty else { return false }

        return cards(in: deck, context: context).contains { card in
            guard normalizedWord(card.word) == wordKey,
                  normalizedSentence(card.sentence) == sentenceKey else {
                return false
            }
            if let cardType {
                return card.cardType == cardType
            }
            return true
        }
    }

    static func matches(
        _ card: FlashCard,
        word: String,
        sentence: String,
        cardType: CardType? = nil
    ) -> Bool {
        let wordKey = normalizedWord(word)
        let sentenceKey = normalizedSentence(sentence)
        guard !wordKey.isEmpty, !sentenceKey.isEmpty else { return false }
        guard normalizedWord(card.word) == wordKey,
              normalizedSentence(card.sentence) == sentenceKey else {
            return false
        }
        if let cardType {
            return card.cardType == cardType
        }
        return true
    }
}

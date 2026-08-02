import Foundation

enum CardContentRegeneratorError: LocalizedError {
    case noMatchingDraft

    var errorDescription: String? {
        switch self {
        case .noMatchingDraft:
            L10n.cardRegenerateNoMatch
        }
    }
}

/// Single-card AI regenerate using the same generator rules as new cards / bulk migrate.
enum CardContentRegenerator {
    @MainActor
    static func regenerate(_ card: FlashCard) async throws {
        let sentence = card.sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        let word = card.word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty, !word.isEmpty else {
            throw CardContentRegeneratorError.noMatchingDraft
        }

        let drafts = try await KimiCardGenerator.generate(
            sentence: sentence,
            words: [word],
            sourceHint: card.sourceAttribution
        )
        guard let draft = matchingDraft(in: drafts, word: word, cardType: card.cardType) else {
            throw CardContentRegeneratorError.noMatchingDraft
        }

        CardContentSync.applyGeneratedContent(draft, to: card)
        DeckCardCountService.notifyCatalogChanged()
    }

    /// Prefer same word + card type; fall back to same word so cloze/definition siblings still update.
    static func matchingDraft(
        in drafts: [GeneratedCardDraft],
        word: String,
        cardType: CardType
    ) -> GeneratedCardDraft? {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        let typed = drafts.first {
            $0.cardType == cardType
                && $0.word.caseInsensitiveCompare(trimmed) == .orderedSame
        }
        if let typed { return typed }
        return drafts.first { $0.word.caseInsensitiveCompare(trimmed) == .orderedSame }
    }
}

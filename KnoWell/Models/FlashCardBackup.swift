import Foundation

extension FlashCardBackup {
    init(from card: FlashCard) {
        self.init(
            id: card.id,
            word: card.word,
            phonetic: card.phonetic,
            sentence: card.sentence,
            cardTypeRaw: card.cardTypeRaw,
            front: card.front,
            back: card.back,
            contextNote: card.contextNote,
            usageNote: card.usageNote,
            etymology: card.etymology,
            synonyms: card.synonyms,
            antonyms: card.antonyms,
            paraphrases: card.paraphrases,
            sourceAttribution: card.sourceAttribution,
            sourceImagePath: card.sourceImagePath,
            highlightText: card.highlightText,
            createdAt: card.createdAt,
            nextReviewDate: card.nextReviewDate,
            intervalDays: card.intervalDays,
            easeFactor: card.easeFactor,
            repetitions: card.repetitions,
            reviewCount: card.reviewCount,
            learningStep: card.learningStep,
            stability: card.stability,
            difficulty: card.difficulty,
            fsrsStateRaw: card.fsrsStateRaw,
            lapses: card.lapses,
            lastReviewDate: card.lastReviewDate,
            isSuspended: card.isSuspended,
            deckId: card.deck?.id
        )
    }

    func apply(to card: FlashCard, deckLookup: [UUID: Deck], defaultDeck: Deck) {
        card.word = word
        card.phonetic = phonetic
        card.sentence = sentence
        card.cardTypeRaw = cardTypeRaw
        card.front = front
        card.back = back
        card.contextNote = contextNote
        card.usageNote = usageNote
        card.etymology = etymology
        card.synonyms = synonyms
        card.antonyms = antonyms
        card.paraphrases = paraphrases
        card.sourceAttribution = sourceAttribution
        card.sourceImagePath = sourceImagePath
        card.highlightText = highlightText
        card.createdAt = createdAt
        card.nextReviewDate = nextReviewDate
        card.intervalDays = intervalDays
        card.easeFactor = easeFactor
        card.repetitions = repetitions
        card.reviewCount = reviewCount
        card.learningStep = learningStep
        card.stability = stability
        card.difficulty = difficulty
        card.fsrsStateRaw = fsrsStateRaw
        card.lapses = lapses
        card.lastReviewDate = lastReviewDate
        card.isSuspended = isSuspended
        if let deckId, let deck = deckLookup[deckId] {
            card.deck = deck
        } else {
            card.deck = defaultDeck
        }
    }

    func makeFlashCard(deckLookup: [UUID: Deck], defaultDeck: Deck) -> FlashCard {
        let card = FlashCard(
            word: word,
            sentence: sentence,
            cardType: CardType(rawValue: cardTypeRaw) ?? .definition,
            front: front,
            back: back,
            contextNote: contextNote,
            usageNote: usageNote,
            etymology: etymology,
            synonyms: synonyms,
            antonyms: antonyms,
            paraphrases: paraphrases,
            sourceAttribution: sourceAttribution,
            sourceImagePath: sourceImagePath,
            highlightText: highlightText,
            phonetic: phonetic
        )
        card.id = id
        card.createdAt = createdAt
        card.nextReviewDate = nextReviewDate
        card.intervalDays = intervalDays
        card.easeFactor = easeFactor
        card.repetitions = repetitions
        card.reviewCount = reviewCount
        card.learningStep = learningStep
        card.stability = stability
        card.difficulty = difficulty
        card.fsrsStateRaw = fsrsStateRaw
        card.lapses = lapses
        card.lastReviewDate = lastReviewDate
        card.isSuspended = isSuspended
        if let deckId, let deck = deckLookup[deckId] {
            card.deck = deck
        } else {
            card.deck = defaultDeck
        }
        return card
    }
}

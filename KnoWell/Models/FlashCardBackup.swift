import Foundation

struct FlashCardBackupFile: Codable {
    let version: Int
    let exportedAt: Date
    let decks: [DeckBackup]?
    let cards: [FlashCardBackup]
}

struct FlashCardBackup: Codable {
    let id: UUID
    let word: String
    let phonetic: String?
    let sentence: String
    let cardTypeRaw: String
    let front: String
    let back: String
    let contextNote: String?
    let usageNote: String?
    let etymology: String?
    let synonyms: String?
    let antonyms: String?
    let paraphrases: String?
    let sourceAttribution: String?
    let sourceImagePath: String?
    let highlightText: String?
    let createdAt: Date
    let nextReviewDate: Date
    let intervalDays: Double
    let easeFactor: Double
    let repetitions: Int
    let reviewCount: Int
    let learningStep: Int
    let stability: Double
    let difficulty: Double
    let fsrsStateRaw: Int
    let lapses: Int
    let lastReviewDate: Date?
    let isSuspended: Bool
    let deckId: UUID?

    enum CodingKeys: String, CodingKey {
        case id, word, phonetic, sentence, cardTypeRaw, front, back, contextNote
        case usageNote, etymology, synonyms, antonyms, paraphrases
        case sourceAttribution, sourceImagePath, highlightText
        case createdAt, nextReviewDate, intervalDays, easeFactor, repetitions, reviewCount, learningStep
        case stability, difficulty, fsrsStateRaw, lapses, lastReviewDate
        case isSuspended, deckId
    }

    init(from card: FlashCard) {
        id = card.id
        word = card.word
        phonetic = card.phonetic
        sentence = card.sentence
        cardTypeRaw = card.cardTypeRaw
        front = card.front
        back = card.back
        contextNote = card.contextNote
        usageNote = card.usageNote
        etymology = card.etymology
        synonyms = card.synonyms
        antonyms = card.antonyms
        paraphrases = card.paraphrases
        sourceAttribution = card.sourceAttribution
        sourceImagePath = card.sourceImagePath
        highlightText = card.highlightText
        createdAt = card.createdAt
        nextReviewDate = card.nextReviewDate
        intervalDays = card.intervalDays
        easeFactor = card.easeFactor
        repetitions = card.repetitions
        reviewCount = card.reviewCount
        learningStep = card.learningStep
        stability = card.stability
        difficulty = card.difficulty
        fsrsStateRaw = card.fsrsStateRaw
        lapses = card.lapses
        lastReviewDate = card.lastReviewDate
        isSuspended = card.isSuspended
        deckId = card.deck?.id
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        word = try container.decode(String.self, forKey: .word)
        phonetic = try container.decodeIfPresent(String.self, forKey: .phonetic)
        sentence = try container.decode(String.self, forKey: .sentence)
        cardTypeRaw = try container.decode(String.self, forKey: .cardTypeRaw)
        front = try container.decode(String.self, forKey: .front)
        back = try container.decode(String.self, forKey: .back)
        contextNote = try container.decodeIfPresent(String.self, forKey: .contextNote)
        usageNote = try container.decodeIfPresent(String.self, forKey: .usageNote)
        etymology = try container.decodeIfPresent(String.self, forKey: .etymology)
        synonyms = try container.decodeIfPresent(String.self, forKey: .synonyms)
        antonyms = try container.decodeIfPresent(String.self, forKey: .antonyms)
        paraphrases = try container.decodeIfPresent(String.self, forKey: .paraphrases)
        sourceAttribution = try container.decodeIfPresent(String.self, forKey: .sourceAttribution)
        sourceImagePath = try container.decodeIfPresent(String.self, forKey: .sourceImagePath)
        highlightText = try container.decodeIfPresent(String.self, forKey: .highlightText)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        nextReviewDate = try container.decode(Date.self, forKey: .nextReviewDate)
        intervalDays = try container.decode(Double.self, forKey: .intervalDays)
        easeFactor = try container.decode(Double.self, forKey: .easeFactor)
        repetitions = try container.decode(Int.self, forKey: .repetitions)
        reviewCount = try container.decodeIfPresent(Int.self, forKey: .reviewCount) ?? 0
        learningStep = try container.decodeIfPresent(Int.self, forKey: .learningStep) ?? 0
        stability = try container.decodeIfPresent(Double.self, forKey: .stability) ?? 0
        difficulty = try container.decodeIfPresent(Double.self, forKey: .difficulty) ?? 0
        fsrsStateRaw = try container.decodeIfPresent(Int.self, forKey: .fsrsStateRaw) ?? 0
        lapses = try container.decodeIfPresent(Int.self, forKey: .lapses) ?? 0
        lastReviewDate = try container.decodeIfPresent(Date.self, forKey: .lastReviewDate)
        isSuspended = try container.decodeIfPresent(Bool.self, forKey: .isSuspended) ?? false
        deckId = try container.decodeIfPresent(UUID.self, forKey: .deckId)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(word, forKey: .word)
        try container.encode(phonetic, forKey: .phonetic)
        try container.encode(sentence, forKey: .sentence)
        try container.encode(cardTypeRaw, forKey: .cardTypeRaw)
        try container.encode(front, forKey: .front)
        try container.encode(back, forKey: .back)
        try container.encode(contextNote, forKey: .contextNote)
        try container.encodeIfPresent(usageNote, forKey: .usageNote)
        try container.encodeIfPresent(etymology, forKey: .etymology)
        try container.encodeIfPresent(synonyms, forKey: .synonyms)
        try container.encodeIfPresent(antonyms, forKey: .antonyms)
        try container.encodeIfPresent(paraphrases, forKey: .paraphrases)
        try container.encodeIfPresent(sourceAttribution, forKey: .sourceAttribution)
        try container.encodeIfPresent(sourceImagePath, forKey: .sourceImagePath)
        try container.encodeIfPresent(highlightText, forKey: .highlightText)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(nextReviewDate, forKey: .nextReviewDate)
        try container.encode(intervalDays, forKey: .intervalDays)
        try container.encode(easeFactor, forKey: .easeFactor)
        try container.encode(repetitions, forKey: .repetitions)
        try container.encode(reviewCount, forKey: .reviewCount)
        try container.encode(learningStep, forKey: .learningStep)
        try container.encode(stability, forKey: .stability)
        try container.encode(difficulty, forKey: .difficulty)
        try container.encode(fsrsStateRaw, forKey: .fsrsStateRaw)
        try container.encode(lapses, forKey: .lapses)
        try container.encodeIfPresent(lastReviewDate, forKey: .lastReviewDate)
        try container.encode(isSuspended, forKey: .isSuspended)
        try container.encode(deckId, forKey: .deckId)
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

import Foundation

struct FlashCardBackupFile: Codable {
    let version: Int
    let exportedAt: Date
    let cards: [FlashCardBackup]
}

struct FlashCardBackup: Codable {
    let id: UUID
    let word: String
    let sentence: String
    let cardTypeRaw: String
    let front: String
    let back: String
    let contextNote: String?
    let createdAt: Date
    let nextReviewDate: Date
    let intervalDays: Double
    let easeFactor: Double
    let repetitions: Int
    let reviewCount: Int
    let learningStep: Int

    enum CodingKeys: String, CodingKey {
        case id, word, sentence, cardTypeRaw, front, back, contextNote
        case createdAt, nextReviewDate, intervalDays, easeFactor, repetitions, reviewCount, learningStep
    }

    init(from card: FlashCard) {
        id = card.id
        word = card.word
        sentence = card.sentence
        cardTypeRaw = card.cardTypeRaw
        front = card.front
        back = card.back
        contextNote = card.contextNote
        createdAt = card.createdAt
        nextReviewDate = card.nextReviewDate
        intervalDays = card.intervalDays
        easeFactor = card.easeFactor
        repetitions = card.repetitions
        reviewCount = card.reviewCount
        learningStep = card.learningStep
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        word = try container.decode(String.self, forKey: .word)
        sentence = try container.decode(String.self, forKey: .sentence)
        cardTypeRaw = try container.decode(String.self, forKey: .cardTypeRaw)
        front = try container.decode(String.self, forKey: .front)
        back = try container.decode(String.self, forKey: .back)
        contextNote = try container.decodeIfPresent(String.self, forKey: .contextNote)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        nextReviewDate = try container.decode(Date.self, forKey: .nextReviewDate)
        intervalDays = try container.decode(Double.self, forKey: .intervalDays)
        easeFactor = try container.decode(Double.self, forKey: .easeFactor)
        repetitions = try container.decode(Int.self, forKey: .repetitions)
        reviewCount = try container.decodeIfPresent(Int.self, forKey: .reviewCount) ?? 0
        learningStep = try container.decodeIfPresent(Int.self, forKey: .learningStep) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(word, forKey: .word)
        try container.encode(sentence, forKey: .sentence)
        try container.encode(cardTypeRaw, forKey: .cardTypeRaw)
        try container.encode(front, forKey: .front)
        try container.encode(back, forKey: .back)
        try container.encode(contextNote, forKey: .contextNote)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(nextReviewDate, forKey: .nextReviewDate)
        try container.encode(intervalDays, forKey: .intervalDays)
        try container.encode(easeFactor, forKey: .easeFactor)
        try container.encode(repetitions, forKey: .repetitions)
        try container.encode(reviewCount, forKey: .reviewCount)
        try container.encode(learningStep, forKey: .learningStep)
    }

    func apply(to card: FlashCard) {
        card.word = word
        card.sentence = sentence
        card.cardTypeRaw = cardTypeRaw
        card.front = front
        card.back = back
        card.contextNote = contextNote
        card.createdAt = createdAt
        card.nextReviewDate = nextReviewDate
        card.intervalDays = intervalDays
        card.easeFactor = easeFactor
        card.repetitions = repetitions
        card.reviewCount = reviewCount
        card.learningStep = learningStep
    }

    func makeFlashCard() -> FlashCard {
        let card = FlashCard(
            word: word,
            sentence: sentence,
            cardType: CardType(rawValue: cardTypeRaw) ?? .definition,
            front: front,
            back: back,
            contextNote: contextNote
        )
        card.id = id
        card.createdAt = createdAt
        card.nextReviewDate = nextReviewDate
        card.intervalDays = intervalDays
        card.easeFactor = easeFactor
        card.repetitions = repetitions
        card.reviewCount = reviewCount
        card.learningStep = learningStep
        return card
    }
}

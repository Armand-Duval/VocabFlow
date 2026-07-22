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
        return card
    }
}

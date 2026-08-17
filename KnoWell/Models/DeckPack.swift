import Foundation

struct DeckPackFile: Codable {
    let version: Int
    let name: String
    let detailText: String?
    let slug: String?
    let cards: [DeckPackCard]
}

struct DeckPackCard: Codable {
    let word: String
    let phonetic: String?
    let sentence: String
    let cardType: String?
    let front: String
    let back: String
    let contextNote: String?
    let synonyms: String?
    let sourceAttribution: String?

    init(
        word: String,
        phonetic: String? = nil,
        sentence: String,
        cardType: String? = nil,
        front: String,
        back: String,
        contextNote: String? = nil,
        synonyms: String? = nil,
        sourceAttribution: String? = nil
    ) {
        self.word = word
        self.phonetic = phonetic
        self.sentence = sentence
        self.cardType = cardType
        self.front = front
        self.back = back
        self.contextNote = contextNote
        self.synonyms = synonyms
        self.sourceAttribution = sourceAttribution
    }
}

struct DeckBackup: Codable, Hashable {
    let id: UUID
    let name: String
    let detailText: String?
    let slug: String?
    let isBuiltIn: Bool
    let createdAt: Date
    let sortOrder: Int

    init(from deck: Deck) {
        id = deck.id
        name = deck.name
        detailText = deck.detailText
        slug = deck.slug
        isBuiltIn = deck.isBuiltIn
        createdAt = deck.createdAt
        sortOrder = deck.sortOrder
    }

    func makeDeck() -> Deck {
        let deck = Deck(
            name: name,
            detailText: detailText,
            slug: slug,
            isBuiltIn: isBuiltIn,
            sortOrder: sortOrder
        )
        deck.id = id
        deck.createdAt = createdAt
        return deck
    }
}

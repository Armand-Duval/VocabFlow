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

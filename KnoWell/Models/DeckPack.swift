import Foundation

extension DeckBackup {
    init(from deck: Deck) {
        self.init(
            id: deck.id,
            name: deck.name,
            detailText: deck.detailText,
            slug: deck.slug,
            isBuiltIn: deck.isBuiltIn,
            createdAt: deck.createdAt,
            sortOrder: deck.sortOrder
        )
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

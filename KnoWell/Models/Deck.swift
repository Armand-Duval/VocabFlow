import Foundation
import SwiftData

@Model
final class Deck {
    var id: UUID
    var name: String
    var detailText: String?
    var slug: String?
    var isBuiltIn: Bool
    var createdAt: Date
    var sortOrder: Int
    var cachedCardCount: Int = 0

    @Relationship(deleteRule: .nullify, inverse: \FlashCard.deck)
    var cards: [FlashCard] = []

    init(
        name: String,
        detailText: String? = nil,
        slug: String? = nil,
        isBuiltIn: Bool = false,
        sortOrder: Int = 0,
        cachedCardCount: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.detailText = detailText
        self.slug = slug
        self.isBuiltIn = isBuiltIn
        self.createdAt = Date()
        self.sortOrder = sortOrder
        self.cachedCardCount = cachedCardCount
    }

    var cardCount: Int { cachedCardCount }
}

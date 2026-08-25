import Foundation

/// On-disk / downloadable deck pack (not a SwiftData row).
public struct DeckPackFile: Codable, Equatable, Sendable {
    public let version: Int
    public let name: String
    public let detailText: String?
    public let slug: String?
    public let cards: [DeckPackCard]

    public init(
        version: Int,
        name: String,
        detailText: String? = nil,
        slug: String? = nil,
        cards: [DeckPackCard]
    ) {
        self.version = version
        self.name = name
        self.detailText = detailText
        self.slug = slug
        self.cards = cards
    }
}

public struct DeckPackCard: Codable, Equatable, Sendable {
    public let word: String
    public let phonetic: String?
    public let sentence: String
    public let cardType: String?
    public let front: String
    public let back: String
    public let contextNote: String?
    public let synonyms: String?
    public let sourceAttribution: String?

    public init(
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

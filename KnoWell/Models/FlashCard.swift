import Foundation
import SwiftData

@Model
final class FlashCard {
    var id: UUID
    var word: String
    var phonetic: String?
    var sentence: String
    var cardTypeRaw: String
    var front: String
    var back: String
    var contextNote: String?
    /// Book / article / author attribution when known.
    var sourceAttribution: String?
    /// App Group relative path (`card-images/….jpg`) for the shared / captured source image.
    var sourceImagePath: String?
    var createdAt: Date
    var nextReviewDate: Date
    var intervalDays: Double
    var easeFactor: Double
    var repetitions: Int
    var reviewCount: Int
    var learningStep: Int
    var isSuspended: Bool = false
    var deck: Deck?

    var cardType: CardType {
        get { CardType(rawValue: cardTypeRaw) ?? .definition }
        set { cardTypeRaw = newValue.rawValue }
    }

    /// 复习正面：释义卡用完整原句（兼容旧数据里 front 只有单词）
    var displayFront: String {
        CardContentFormatter.displayFront(
            front: front,
            sentence: sentence,
            word: word,
            cardType: cardType
        )
    }

    /// 复习时显示的背面：合并 back 与 contextNote（兼容旧数据）
    var displayBack: String {
        CardContentFormatter.displayBack(back: back, contextNote: contextNote)
    }

    init(
        word: String,
        sentence: String,
        cardType: CardType,
        front: String,
        back: String,
        contextNote: String? = nil,
        sourceAttribution: String? = nil,
        sourceImagePath: String? = nil,
        phonetic: String? = nil,
        deck: Deck? = nil
    ) {
        self.id = UUID()
        self.word = word
        self.phonetic = phonetic
        self.sentence = sentence
        self.cardTypeRaw = cardType.rawValue
        self.front = front
        self.back = back
        self.contextNote = contextNote
        self.sourceAttribution = sourceAttribution
        self.sourceImagePath = sourceImagePath
        self.deck = deck
        self.createdAt = Date()
        self.nextReviewDate = Date()
        self.intervalDays = 0
        self.easeFactor = 2.5
        self.repetitions = 0
        self.reviewCount = 0
        self.learningStep = 0
        self.isSuspended = false
    }
}

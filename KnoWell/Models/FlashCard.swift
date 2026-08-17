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
    /// Why this word fits here; contrast with near-synonyms / alternatives.
    var usageNote: String?
    /// Root / affix / morphology note when useful.
    var etymology: String?
    /// Near-synonyms / substitutes for lookup (stored as joined list text).
    var synonyms: String?
    /// Opposites / contrasts for lookup (stored as joined list text).
    var antonyms: String?
    /// 1–2 transferable model sentences (scene-tagged multiline text).
    var paraphrases: String?
    /// Book / article / author attribution when known.
    var sourceAttribution: String?
    /// App Group relative path (`card-images/….jpg`) for the shared / captured source image.
    var sourceImagePath: String?
    /// Manual sentence highlight override; when nil, `word` is highlighted.
    var highlightText: String?
    var createdAt: Date
    var nextReviewDate: Date
    var intervalDays: Double
    var easeFactor: Double
    var repetitions: Int
    var reviewCount: Int
    var learningStep: Int
    /// FSRS stability (days); 0 means not yet migrated / new.
    var stability: Double = 0
    /// FSRS difficulty in 1...10.
    var difficulty: Double = 0
    /// `FSRSCardState` raw value.
    var fsrsStateRaw: Int = 0
    var lapses: Int = 0
    var lastReviewDate: Date?
    var isSuspended: Bool = false
    var deck: Deck?

    var cardType: CardType {
        get { CardType(rawValue: cardTypeRaw) ?? .definition }
        set { cardTypeRaw = newValue.rawValue }
    }

    /// Phrase highlighted in the study sentence (manual override or study word).
    var displayHighlight: String {
        studyContent.displayHighlight
    }

    /// 复习正面：释义卡用完整原句（兼容旧数据里 front 只有单词）
    var displayFront: String {
        studyContent.displayFront
    }

    /// 复习时显示的背面：合并 back 与 contextNote（兼容旧数据）
    var displayBack: String {
        studyContent.displayBack
    }

    var studyContent: CardStudyContent {
        CardStudyContent(
            word: word,
            phonetic: phonetic,
            sentence: sentence,
            cardType: cardType,
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
            highlightText: highlightText
        )
    }

    init(
        word: String,
        sentence: String,
        cardType: CardType,
        front: String,
        back: String,
        contextNote: String? = nil,
        usageNote: String? = nil,
        etymology: String? = nil,
        synonyms: String? = nil,
        antonyms: String? = nil,
        paraphrases: String? = nil,
        sourceAttribution: String? = nil,
        sourceImagePath: String? = nil,
        highlightText: String? = nil,
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
        self.usageNote = usageNote
        self.etymology = etymology
        self.synonyms = synonyms
        self.antonyms = antonyms
        self.paraphrases = paraphrases
        self.sourceAttribution = sourceAttribution
        self.sourceImagePath = sourceImagePath
        self.highlightText = highlightText
        self.deck = deck
        self.createdAt = Date()
        self.nextReviewDate = Date()
        self.intervalDays = 0
        self.easeFactor = 2.5
        self.repetitions = 0
        self.reviewCount = 0
        self.learningStep = 0
        self.stability = 0
        self.difficulty = 0
        self.fsrsStateRaw = FSRSCardState.new.rawValue
        self.lapses = 0
        self.lastReviewDate = nil
        self.isSuspended = false
    }
}

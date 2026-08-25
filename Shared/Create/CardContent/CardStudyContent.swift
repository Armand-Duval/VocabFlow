import Foundation

/// Display snapshot shared by review and create-preview.
public struct CardStudyContent: Equatable, Sendable {
    public var word: String
    public var phonetic: String?
    public var sentence: String
    public var cardType: CardType
    public var front: String
    public var back: String
    public var contextNote: String?
    public var usageNote: String?
    public var etymology: String?
    public var synonyms: String?
    public var antonyms: String?
    public var paraphrases: String?
    public var sourceAttribution: String?
    public var sourceImagePath: String?
    public var highlightText: String?

    public init(
        word: String,
        phonetic: String? = nil,
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
        highlightText: String? = nil
    ) {
        self.word = word
        self.phonetic = phonetic
        self.sentence = sentence
        self.cardType = cardType
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
    }

    public var displayHighlight: String {
        let custom = highlightText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !custom.isEmpty { return custom }
        return word
    }

    public var displayFront: String {
        CardContentFormatter.displayFront(
            front: front,
            sentence: sentence,
            word: word,
            cardType: cardType
        )
    }

    public var displayBack: String {
        displayBack()
    }

    public func displayBack(translationLabel: String = CardContentFormatter.defaultTranslationLabel) -> String {
        CardContentFormatter.displayBack(
            back: back,
            contextNote: contextNote,
            translationLabel: translationLabel
        )
    }
}

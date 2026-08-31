import Foundation

public struct FlashCardBackupFile: Codable, Equatable, Sendable {
    public let version: Int
    public let exportedAt: Date
    public let decks: [DeckBackup]?
    public let cards: [FlashCardBackup]

    public init(
        version: Int,
        exportedAt: Date,
        decks: [DeckBackup]?,
        cards: [FlashCardBackup]
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.decks = decks
        self.cards = cards
    }
}

public struct DeckBackup: Codable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let detailText: String?
    public let slug: String?
    public let isBuiltIn: Bool
    public let createdAt: Date
    public let sortOrder: Int

    public init(
        id: UUID,
        name: String,
        detailText: String? = nil,
        slug: String? = nil,
        isBuiltIn: Bool,
        createdAt: Date,
        sortOrder: Int
    ) {
        self.id = id
        self.name = name
        self.detailText = detailText
        self.slug = slug
        self.isBuiltIn = isBuiltIn
        self.createdAt = createdAt
        self.sortOrder = sortOrder
    }
}

/// Full card snapshot for backup / apkg sidecar. Schedule fields are raw numbers.
public struct FlashCardBackup: Codable, Equatable, Sendable {
    public let id: UUID
    public let word: String
    public let phonetic: String?
    public let sentence: String
    public let cardTypeRaw: String
    public let front: String
    public let back: String
    public let contextNote: String?
    public let usageNote: String?
    public let etymology: String?
    public let synonyms: String?
    public let antonyms: String?
    public let paraphrases: String?
    public let sourceAttribution: String?
    public let sourceImagePath: String?
    public let highlightText: String?
    public let createdAt: Date
    public let nextReviewDate: Date
    public let intervalDays: Double
    public let easeFactor: Double
    public let repetitions: Int
    public let reviewCount: Int
    public let learningStep: Int
    public let stability: Double
    public let difficulty: Double
    public let fsrsStateRaw: Int
    public let lapses: Int
    public let lastReviewDate: Date?
    public let isSuspended: Bool
    public let deckId: UUID?

    enum CodingKeys: String, CodingKey {
        case id, word, phonetic, sentence, cardTypeRaw, front, back, contextNote
        case usageNote, etymology, synonyms, antonyms, paraphrases
        case sourceAttribution, sourceImagePath, highlightText
        case createdAt, nextReviewDate, intervalDays, easeFactor, repetitions, reviewCount, learningStep
        case stability, difficulty, fsrsStateRaw, lapses, lastReviewDate
        case isSuspended, deckId
    }

    public init(
        id: UUID,
        word: String,
        phonetic: String? = nil,
        sentence: String,
        cardTypeRaw: String,
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
        createdAt: Date,
        nextReviewDate: Date,
        intervalDays: Double,
        easeFactor: Double,
        repetitions: Int,
        reviewCount: Int,
        learningStep: Int,
        stability: Double,
        difficulty: Double,
        fsrsStateRaw: Int,
        lapses: Int,
        lastReviewDate: Date?,
        isSuspended: Bool,
        deckId: UUID?
    ) {
        self.id = id
        self.word = word
        self.phonetic = phonetic
        self.sentence = sentence
        self.cardTypeRaw = cardTypeRaw
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
        self.createdAt = createdAt
        self.nextReviewDate = nextReviewDate
        self.intervalDays = intervalDays
        self.easeFactor = easeFactor
        self.repetitions = repetitions
        self.reviewCount = reviewCount
        self.learningStep = learningStep
        self.stability = stability
        self.difficulty = difficulty
        self.fsrsStateRaw = fsrsStateRaw
        self.lapses = lapses
        self.lastReviewDate = lastReviewDate
        self.isSuspended = isSuspended
        self.deckId = deckId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        word = try container.decode(String.self, forKey: .word)
        phonetic = try container.decodeIfPresent(String.self, forKey: .phonetic)
        sentence = try container.decode(String.self, forKey: .sentence)
        cardTypeRaw = try container.decode(String.self, forKey: .cardTypeRaw)
        front = try container.decode(String.self, forKey: .front)
        back = try container.decode(String.self, forKey: .back)
        contextNote = try container.decodeIfPresent(String.self, forKey: .contextNote)
        usageNote = try container.decodeIfPresent(String.self, forKey: .usageNote)
        etymology = try container.decodeIfPresent(String.self, forKey: .etymology)
        synonyms = try container.decodeIfPresent(String.self, forKey: .synonyms)
        antonyms = try container.decodeIfPresent(String.self, forKey: .antonyms)
        paraphrases = try container.decodeIfPresent(String.self, forKey: .paraphrases)
        sourceAttribution = try container.decodeIfPresent(String.self, forKey: .sourceAttribution)
        sourceImagePath = try container.decodeIfPresent(String.self, forKey: .sourceImagePath)
        highlightText = try container.decodeIfPresent(String.self, forKey: .highlightText)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        nextReviewDate = try container.decode(Date.self, forKey: .nextReviewDate)
        intervalDays = try container.decode(Double.self, forKey: .intervalDays)
        easeFactor = try container.decode(Double.self, forKey: .easeFactor)
        repetitions = try container.decode(Int.self, forKey: .repetitions)
        reviewCount = try container.decodeIfPresent(Int.self, forKey: .reviewCount) ?? 0
        learningStep = try container.decodeIfPresent(Int.self, forKey: .learningStep) ?? 0
        stability = try container.decodeIfPresent(Double.self, forKey: .stability) ?? 0
        difficulty = try container.decodeIfPresent(Double.self, forKey: .difficulty) ?? 0
        fsrsStateRaw = try container.decodeIfPresent(Int.self, forKey: .fsrsStateRaw) ?? 0
        lapses = try container.decodeIfPresent(Int.self, forKey: .lapses) ?? 0
        lastReviewDate = try container.decodeIfPresent(Date.self, forKey: .lastReviewDate)
        isSuspended = try container.decodeIfPresent(Bool.self, forKey: .isSuspended) ?? false
        deckId = try container.decodeIfPresent(UUID.self, forKey: .deckId)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(word, forKey: .word)
        try container.encode(phonetic, forKey: .phonetic)
        try container.encode(sentence, forKey: .sentence)
        try container.encode(cardTypeRaw, forKey: .cardTypeRaw)
        try container.encode(front, forKey: .front)
        try container.encode(back, forKey: .back)
        try container.encode(contextNote, forKey: .contextNote)
        try container.encodeIfPresent(usageNote, forKey: .usageNote)
        try container.encodeIfPresent(etymology, forKey: .etymology)
        try container.encodeIfPresent(synonyms, forKey: .synonyms)
        try container.encodeIfPresent(antonyms, forKey: .antonyms)
        try container.encodeIfPresent(paraphrases, forKey: .paraphrases)
        try container.encodeIfPresent(sourceAttribution, forKey: .sourceAttribution)
        try container.encodeIfPresent(sourceImagePath, forKey: .sourceImagePath)
        try container.encodeIfPresent(highlightText, forKey: .highlightText)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(nextReviewDate, forKey: .nextReviewDate)
        try container.encode(intervalDays, forKey: .intervalDays)
        try container.encode(easeFactor, forKey: .easeFactor)
        try container.encode(repetitions, forKey: .repetitions)
        try container.encode(reviewCount, forKey: .reviewCount)
        try container.encode(learningStep, forKey: .learningStep)
        try container.encode(stability, forKey: .stability)
        try container.encode(difficulty, forKey: .difficulty)
        try container.encode(fsrsStateRaw, forKey: .fsrsStateRaw)
        try container.encode(lapses, forKey: .lapses)
        try container.encodeIfPresent(lastReviewDate, forKey: .lastReviewDate)
        try container.encode(isSuspended, forKey: .isSuspended)
        try container.encode(deckId, forKey: .deckId)
    }
}

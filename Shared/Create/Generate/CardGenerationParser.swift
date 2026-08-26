import Foundation

public enum CardGenerationParseError: Error, Equatable {
    case invalidJSON
    case emptyCards
}

public enum CardGenerationParser {
    public static func parse(
        from content: String,
        sentence: String,
        requiredCardType: CardType?
    ) throws -> [CardStudyContent] {
        let response: CardGeneratorResponse
        do {
            response = try AIJSON.decode(CardGeneratorResponse.self, from: content)
        } catch {
            throw CardGenerationParseError.invalidJSON
        }

        let source = response.source?.nilIfEmpty
        var drafts = response.cards.compactMap { item -> CardStudyContent? in
            guard let type = CardType(rawValue: item.type.lowercased()) else { return nil }
            let word = item.word.trimmingCharacters(in: .whitespacesAndNewlines)
            let back = item.back.trimmingCharacters(in: .whitespacesAndNewlines)
            return CardStudyContent(
                word: word,
                phonetic: normalizedPhonetic(item.phonetic),
                sentence: sentence,
                cardType: type,
                front: CardContentFormatter.normalizedFront(
                    front: item.front,
                    sentence: sentence,
                    word: word,
                    cardType: type
                ),
                back: back,
                contextNote: CardContentFormatter.ensureTranslationHighlight(
                    contextNote: item.contextNote,
                    sense: back,
                    explicitHighlight: item.highlight
                ),
                usageNote: item.usageNote?.nilIfEmpty,
                etymology: item.etymology?.nilIfEmpty,
                synonyms: CardContentFormatter.joinRelatedWords(item.synonyms?.values ?? []),
                antonyms: CardContentFormatter.joinRelatedWords(item.antonyms?.values ?? []),
                paraphrases: CardContentFormatter.encodeParaphrases(item.decodedParaphrases),
                sourceAttribution: source
            )
        }

        if let requiredCardType {
            drafts = drafts.filter { $0.cardType == requiredCardType }
        }
        guard !drafts.isEmpty else { throw CardGenerationParseError.emptyCards }

        var phoneticByWord: [String: String] = [:]
        for draft in drafts {
            if let phonetic = draft.phonetic, !phonetic.isEmpty {
                phoneticByWord[draft.word.lowercased()] = phonetic
            }
        }
        for index in drafts.indices {
            if drafts[index].phonetic == nil,
               let shared = phoneticByWord[drafts[index].word.lowercased()] {
                drafts[index].phonetic = shared
            }
        }
        return drafts
    }

    private static func normalizedPhonetic(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        if let colon = value.firstIndex(of: ":"),
           value[..<colon].lowercased().contains("ipa") {
            value = String(value[value.index(after: colon)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if value.contains("/") || value.contains("[") {
            // LLMs often mark stress with ASCII / curly quotes instead of ˈ.
            value = value
                .replacingOccurrences(of: "\u{2019}", with: "ˈ")
                .replacingOccurrences(of: "'", with: "ˈ")
        }
        return value.nilIfEmpty
    }
}

struct CardGeneratorResponse: Decodable {
    let source: String?
    let cards: [CardGeneratorItem]
}

struct CardGeneratorItem: Decodable {
    let word: String
    let phonetic: String?
    let type: String
    let front: String
    let back: String
    let contextNote: String?
    let highlight: String?
    let usageNote: String?
    let etymology: String?
    let synonyms: FlexibleStringList?
    let antonyms: FlexibleStringList?
    let paraphrases: [CardGeneratorParaphrase]?

    enum CodingKeys: String, CodingKey {
        case word, phonetic, type, front, back, highlight, etymology
        case synonyms, antonyms, paraphrases
        case contextNote = "context_note"
        case usageNote = "usage_note"
    }

    var decodedParaphrases: [CardParaphrase] {
        (paraphrases ?? []).compactMap { item in
            let sentence = (item.en ?? item.sentence ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sentence.isEmpty else { return nil }
            let scene = (item.scene ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let note = (item.zh ?? item.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return CardParaphrase(
                scene: scene,
                sentence: sentence,
                note: note.isEmpty ? nil : note
            )
        }
    }
}

struct CardGeneratorParaphrase: Decodable {
    let scene: String?
    let en: String?
    let sentence: String?
    let zh: String?
    let note: String?
}

struct FlexibleStringList: Decodable {
    let values: [String]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let list = try? container.decode([String].self) {
            values = list
            return
        }
        if let text = try? container.decode(String.self) {
            values = CardContentFormatter.splitRelatedWords(text)
            return
        }
        values = []
    }
}

fileprivate extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

import Foundation

enum DeckPackConverter {
    static func deckPack(
        from data: Data,
        format: DeckRemotePackFormat,
        remote: DeckRemotePack
    ) throws -> DeckPackFile {
        switch format {
        case .deckPack:
            return try JSONDecoder().decode(DeckPackFile.self, from: data)
        case .ngslDefinitions:
            return try convertNGSL(data: data, remote: remote)
        case .toeflEssential:
            return try convertTOEFL(data: data, remote: remote)
        case .nawlLemma:
            return try convertNAWL(data: data, remote: remote)
        }
    }

    private static func convertNGSL(data: Data, remote: DeckRemotePack) throws -> DeckPackFile {
        struct NGSLRow: Decodable {
            let Word: String
            let Definitions: String
        }

        let rows = try JSONDecoder().decode([NGSLRow].self, from: data)
        let cards = rows.compactMap { row -> DeckPackCard? in
            let word = row.Word.trimmingCharacters(in: .whitespacesAndNewlines)
            let definition = row.Definitions.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !word.isEmpty else { return nil }
            return DeckPackCard(
                word: word,
                phonetic: nil,
                sentence: "",
                cardType: CardType.definition.rawValue,
                front: word,
                back: definition,
                contextNote: nil,
                sourceAttribution: remote.name
            )
        }

        return DeckPackFile(
            version: 1,
            name: remote.name,
            detailText: remote.detailText,
            slug: remote.slug,
            cards: cards
        )
    }

    private static func convertTOEFL(data: Data, remote: DeckRemotePack) throws -> DeckPackFile {
        struct TOEFLRow: Decodable {
            let word: String
            let pos: String?
            let definition_en: String
            let example_sentence: String
            let synonyms: [String]?
            let theme: String?
        }

        let rows = try JSONDecoder().decode([TOEFLRow].self, from: data)
        let cards = rows.compactMap { row -> DeckPackCard? in
            let word = row.word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !word.isEmpty else { return nil }
            let posSuffix = row.pos.map { " (\($0))" } ?? ""
            let definition = row.definition_en.trimmingCharacters(in: .whitespacesAndNewlines)
            let example = row.example_sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            let synonyms = row.synonyms?
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            let theme = row.theme?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let source = [theme, remote.name].filter { !$0.isEmpty }.joined(separator: " · ")
            return DeckPackCard(
                word: word,
                phonetic: nil,
                sentence: example,
                cardType: CardType.definition.rawValue,
                front: example.isEmpty ? word : example,
                back: definition.isEmpty ? "\(word)\(posSuffix)" : "\(word)\(posSuffix)\n\n\(definition)",
                contextNote: nil,
                synonyms: synonyms?.isEmpty == false ? synonyms : nil,
                sourceAttribution: source.isEmpty ? nil : source
            )
        }

        return DeckPackFile(
            version: 1,
            name: remote.name,
            detailText: remote.detailText,
            slug: remote.slug,
            cards: cards
        )
    }

    private static func convertNAWL(data: Data, remote: DeckRemotePack) throws -> DeckPackFile {
        let lemmaMap = try JSONDecoder().decode([String: [String]].self, from: data)
        let sortedWords = lemmaMap.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        let cards = sortedWords.compactMap { word -> DeckPackCard? in
            let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let related = lemmaMap[word]?
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.caseInsensitiveCompare(trimmed) != .orderedSame } ?? []
            return DeckPackCard(
                word: trimmed,
                phonetic: nil,
                sentence: "",
                cardType: CardType.definition.rawValue,
                front: trimmed,
                back: related.isEmpty ? trimmed : related.joined(separator: ", "),
                contextNote: nil,
                synonyms: related.isEmpty ? nil : related.joined(separator: ", "),
                sourceAttribution: remote.name
            )
        }

        return DeckPackFile(
            version: 1,
            name: remote.name,
            detailText: remote.detailText,
            slug: remote.slug,
            cards: cards
        )
    }
}

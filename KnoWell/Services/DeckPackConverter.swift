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
        let cards = rows.map { row in
            DeckPackCard(
                word: row.Word,
                phonetic: nil,
                sentence: row.Definitions,
                cardType: CardType.definition.rawValue,
                front: row.Word,
                back: "\(row.Word)\n\n\(row.Definitions)",
                contextNote: "NGSL 1.2"
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
        }

        let rows = try JSONDecoder().decode([TOEFLRow].self, from: data)
        let cards = rows.map { row in
            let posSuffix = row.pos.map { " (\($0))" } ?? ""
            return DeckPackCard(
                word: row.word,
                phonetic: nil,
                sentence: row.example_sentence,
                cardType: CardType.definition.rawValue,
                front: row.word,
                back: "\(row.word)\(posSuffix)\n\n\(row.definition_en)",
                contextNote: row.pos
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

        let cards = sortedWords.map { word in
            let related = lemmaMap[word]?.filter { $0.caseInsensitiveCompare(word) != .orderedSame } ?? []
            let relatedNote = related.isEmpty ? "" : "\nRelated: \(related.joined(separator: ", "))"
            let definition = "Academic vocabulary (NAWL 1.2).\(relatedNote)"

            return DeckPackCard(
                word: word,
                phonetic: nil,
                sentence: definition,
                cardType: CardType.definition.rawValue,
                front: word,
                back: "\(word)\n\n\(definition)",
                contextNote: "NAWL 1.2"
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

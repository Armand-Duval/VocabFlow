import Foundation

enum CardType: String, Codable, CaseIterable {
    case cloze
    case definition

    var displayName: String {
        switch self {
        case .cloze: L10n.cardTypeCloze
        case .definition: L10n.cardTypeDefinition
        }
    }
}

struct GeneratedCardDraft: Identifiable, Equatable {
    let id = UUID()
    var word: String
    var sentence: String
    var cardType: CardType
    var front: String
    var back: String
    var contextNote: String?
    var isSelected: Bool = true
}

enum CardContentFormatter {
    static func displayBack(back: String, contextNote: String?) -> String {
        let trimmedBack = back.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let note = contextNote?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty else {
            return trimmedBack
        }
        if trimmedBack.contains(note) { return trimmedBack }
        if trimmedBack.isEmpty { return note }
        return trimmedBack + "\n\n" + note
    }

    static func mergedBack(back: String, contextNote: String?) -> String {
        displayBack(back: back, contextNote: contextNote)
    }
}

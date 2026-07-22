import Foundation

struct DeckCommunityEntry: Identifiable {
    let id: String
    let name: String
    let detailText: String
    let ankiWebURL: URL
    let estimatedCards: Int?
    let category: String

    var cardCountLabel: String? {
        guard let estimatedCards else { return nil }
        return L10n.deckCommunityEstimatedCards(estimatedCards)
    }
}

enum DeckCommunityCatalog {
    static let entries: [DeckCommunityEntry] = [
        DeckCommunityEntry(
            id: "ielts-4000",
            name: L10n.deckCommunityIELTS4000Name,
            detailText: L10n.deckCommunityIELTS4000Detail,
            ankiWebURL: URL(string: "https://ankiweb.net/shared/info/238128422")!,
            estimatedCards: 4000,
            category: "IELTS"
        ),
        DeckCommunityEntry(
            id: "english-60k",
            name: L10n.deckCommunityEnglish60kName,
            detailText: L10n.deckCommunityEnglish60kDetail,
            ankiWebURL: URL(string: "https://ankiweb.net/shared/info/365554322")!,
            estimatedCards: 60000,
            category: "General"
        ),
        DeckCommunityEntry(
            id: "advanced-vocab",
            name: L10n.deckCommunityAdvancedVocabName,
            detailText: L10n.deckCommunityAdvancedVocabDetail,
            ankiWebURL: URL(string: "https://ankiweb.net/shared/info/1980021227")!,
            estimatedCards: 5000,
            category: "General"
        ),
        DeckCommunityEntry(
            id: "anki-search-gre",
            name: L10n.deckCommunityGRESearchName,
            detailText: L10n.deckCommunityGRESearchDetail,
            ankiWebURL: URL(string: "https://ankiweb.net/shared/decks?search=GRE")!,
            estimatedCards: nil,
            category: "GRE"
        ),
        DeckCommunityEntry(
            id: "anki-search-toefl",
            name: L10n.deckCommunityTOEFLSearchName,
            detailText: L10n.deckCommunityTOEFLSearchDetail,
            ankiWebURL: URL(string: "https://ankiweb.net/shared/decks?search=TOEFL")!,
            estimatedCards: nil,
            category: "TOEFL"
        )
    ]
}

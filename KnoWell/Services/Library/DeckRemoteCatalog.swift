import Foundation

enum DeckRemotePackFormat: String, Codable {
    case deckPack
    case ngslDefinitions
    case toeflEssential
    case nawlLemma
}

struct DeckRemotePack: Identifiable {
    let id: String
    let slug: String
    let name: String
    let detailText: String
    let url: URL
    let format: DeckRemotePackFormat
    let cardCount: Int
    let license: String
    let attributionURL: URL

    var cardCountLabel: String {
        L10n.deckCardCount(cardCount)
    }

    var licenseLabel: String {
        L10n.deckRemoteLicense(license)
    }

    /// What the download URL actually is — not the official spreadsheet / Anki deck.
    var sourceFormatLabel: String {
        L10n.deckSourceFormatJSON
    }
}

enum DeckRemoteCatalog {
    /// Prefer direct-install packs (TOEFL/IELTS 1000) first, then other open lists.
    static let packs: [DeckRemotePack] = [
        DeckRemotePack(
            id: "toefl-ielts-1000",
            slug: "toefl-ielts-1000",
            name: L10n.deckRemoteTOEFLName,
            detailText: L10n.deckRemoteTOEFLDetail,
            url: URL(string: "https://raw.githubusercontent.com/anlecute/toefl-essential-vocabulary-dataset/main/toefl_essential_vocabulary.json")!,
            format: .toeflEssential,
            cardCount: 1000,
            license: "MIT",
            attributionURL: URL(string: "https://github.com/anlecute/toefl-essential-vocabulary-dataset")!
        ),
        DeckRemotePack(
            id: "ngsl-1.2",
            slug: "ngsl-1.2",
            name: L10n.deckRemoteNGSLName,
            detailText: L10n.deckRemoteNGSLDetail,
            url: URL(string: "https://raw.githubusercontent.com/FabriceBoyer/word_lists/main/ngsl/1.2/json/NGSL_1.2_with_English_definitions.json")!,
            format: .ngslDefinitions,
            cardCount: 2809,
            license: "CC BY-SA 4.0",
            attributionURL: URL(string: "https://www.newgeneralservicelist.com/new-general-service-list")!
        ),
        DeckRemotePack(
            id: "nawl-1.2",
            slug: "nawl-1.2",
            name: L10n.deckRemoteNAWLName,
            detailText: L10n.deckRemoteNAWLDetail,
            url: URL(string: "https://raw.githubusercontent.com/lpmi-13/machine_readable_wordlists/master/Academic/NAWL/NAWL.json")!,
            format: .nawlLemma,
            cardCount: 963,
            license: "CC BY-SA 4.0",
            attributionURL: URL(string: "https://www.newgeneralservicelist.com/new-academic-word-list")!
        )
    ]

    static func pack(for id: String) -> DeckRemotePack? {
        packs.first { $0.id == id }
    }
}

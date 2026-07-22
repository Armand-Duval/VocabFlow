import Foundation

struct DeckCatalogPreset: Identifiable {
    let slug: String
    let name: String
    let detailText: String
    let packFilename: String
    let sortOrder: Int

    var id: String { slug }

    var starterCardCount: Int {
        DeckCatalog.starterCount(for: packFilename)
    }
}

enum DeckCatalog {
    static let defaultSlug = "default"

    static var presets: [DeckCatalogPreset] {
        [
            DeckCatalogPreset(
                slug: "ielts-core",
                name: L10n.deckPresetIELTSName,
                detailText: L10n.deckPresetIELTSDetail,
                packFilename: "ielts-core",
                sortOrder: 10
            ),
            DeckCatalogPreset(
                slug: "gre-high-frequency",
                name: L10n.deckPresetGREName,
                detailText: L10n.deckPresetGREDetail,
                packFilename: "gre-high-frequency",
                sortOrder: 20
            ),
            DeckCatalogPreset(
                slug: "economist-reading",
                name: L10n.deckPresetEconomistName,
                detailText: L10n.deckPresetEconomistDetail,
                packFilename: "economist-reading",
                sortOrder: 30
            ),
            DeckCatalogPreset(
                slug: "poor-charlies-almanack",
                name: L10n.deckPresetPoorCharliesName,
                detailText: L10n.deckPresetPoorCharliesDetail,
                packFilename: "poor-charlies-almanack",
                sortOrder: 40
            )
        ]
    }

    static func preset(for slug: String) -> DeckCatalogPreset? {
        presets.first { $0.slug == slug }
    }

    static func starterCount(for packFilename: String) -> Int {
        loadBundledPack(named: packFilename)?.cards.count ?? 0
    }

    static func loadBundledPack(named filename: String) -> DeckPackFile? {
        guard let url = Bundle.main.url(forResource: filename, withExtension: "json", subdirectory: "DeckPacks")
            ?? Bundle.main.url(forResource: filename, withExtension: "json") else {
            return nil
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(DeckPackFile.self, from: data)
    }
}

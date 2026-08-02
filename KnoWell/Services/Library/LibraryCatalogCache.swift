import Foundation

struct LibraryListCacheEntry: Sendable {
    let groups: [LibraryWordGroup]
    let flatCardIDs: [UUID]
    let dueCardIDs: [UUID]
    let useFlatList: Bool
}

@Observable
@MainActor
final class LibraryCatalogCache {
    static let shared = LibraryCatalogCache()

    private var listEntries: [String: LibraryListCacheEntry] = [:]

    func invalidateListCache() {
        listEntries.removeAll()
    }

    func invalidateAll() {
        invalidateListCache()
    }

    func cacheKey(
        filterDeckID: UUID?,
        search: String,
        cardCount: Int,
        cardFilter: String = "all",
        forceGrouped: Bool = false
    ) -> String {
        let mode = forceGrouped ? "grouped" : "auto"
        return "\(filterDeckID?.uuidString ?? "all")|\(search.lowercased())|\(cardCount)|\(cardFilter)|\(mode)"
    }

    func cachedList(for key: String) -> LibraryListCacheEntry? {
        listEntries[key]
    }

    func store(_ entry: LibraryListCacheEntry, for key: String) {
        listEntries[key] = entry
    }

    func totalCount(from decks: [Deck]) -> Int {
        decks.reduce(0) { $0 + $1.cachedCardCount }
    }

    func deckCounts(from decks: [Deck]) -> [UUID: Int] {
        Dictionary(uniqueKeysWithValues: decks.map { ($0.id, $0.cachedCardCount) })
    }
}

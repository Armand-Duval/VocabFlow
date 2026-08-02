import Foundation

struct LibraryCardSnapshot: Sendable {
    let id: UUID
    let word: String
    let wordKey: String
    let createdAt: TimeInterval
    let sentence: String
    let front: String
    let back: String
    let contextNote: String?
    let deckName: String?
    let deckID: UUID?
    let isDue: Bool
}

struct LibraryWordGroup: Sendable, Identifiable {
    let wordKey: String
    let word: String
    let cardIDs: [UUID]

    var id: String { wordKey }
}

struct LibrarySearchIndex: Sendable {
    private let tokensByCardID: [UUID: [String]]

    static func build(from snapshots: [LibraryCardSnapshot]) -> LibrarySearchIndex {
        var map: [UUID: [String]] = [:]
        map.reserveCapacity(snapshots.count)
        for snapshot in snapshots {
            map[snapshot.id] = tokenize(snapshot)
        }
        return LibrarySearchIndex(tokensByCardID: map)
    }

    func matchingSnapshots(in snapshots: [LibraryCardSnapshot], query: String) -> [LibraryCardSnapshot] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return snapshots }

        let needleTokens = Self.normalize(trimmed)
        guard !needleTokens.isEmpty else { return snapshots }

        return snapshots.filter { snapshot in
            guard let haystack = tokensByCardID[snapshot.id] else { return false }
            return needleTokens.allSatisfy { token in
                haystack.contains(where: { $0.hasPrefix(token) || $0.contains(token) })
            }
        }
    }

    private static func tokenize(_ snapshot: LibraryCardSnapshot) -> [String] {
        let combined = [
            snapshot.word,
            snapshot.sentence,
            snapshot.front,
            snapshot.back,
            snapshot.contextNote ?? "",
            snapshot.deckName ?? ""
        ].joined(separator: " ")
        return normalize(combined)
    }

    private static func normalize(_ text: String) -> [String] {
        text
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}

enum LibraryCardGrouper {
    static let groupPageSize = 60
    static let flatListThreshold = 500

    static func makeSnapshots(from cards: [FlashCard], now: Date = .now) -> [LibraryCardSnapshot] {
        cards.map { card in
            LibraryCardSnapshot(
                id: card.id,
                word: card.word,
                wordKey: card.word.lowercased(),
                createdAt: card.createdAt.timeIntervalSince1970,
                sentence: card.sentence,
                front: card.front,
                back: card.back,
                contextNote: card.contextNote,
                deckName: card.deck?.name,
                deckID: card.deck?.id,
                isDue: ReviewScheduler.isDue(card, now: now)
            )
        }
    }

    static func deckCounts(from snapshots: [LibraryCardSnapshot]) -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        counts.reserveCapacity(8)
        for snapshot in snapshots {
            if let deckID = snapshot.deckID {
                counts[deckID, default: 0] += 1
            }
        }
        return counts
    }

    static func shouldUseFlatList(cardCount: Int) -> Bool {
        cardCount >= flatListThreshold
    }

    static func buildListData(
        snapshots: [LibraryCardSnapshot],
        searchQuery: String
    ) -> (groups: [LibraryWordGroup], flatCardIDs: [UUID], useFlatList: Bool, searchIndex: LibrarySearchIndex) {
        let index = LibrarySearchIndex.build(from: snapshots)
        let filtered = index.matchingSnapshots(in: snapshots, query: searchQuery)
        let useFlatList = shouldUseFlatList(cardCount: snapshots.count)

        if useFlatList {
            let flat = filtered
                .sorted { $0.createdAt > $1.createdAt }
                .map(\.id)
            return ([], flat, true, index)
        }

        var grouped: [String: [LibraryCardSnapshot]] = [:]
        grouped.reserveCapacity(min(filtered.count, 4096))
        for snapshot in filtered {
            grouped[snapshot.wordKey, default: []].append(snapshot)
        }

        let groups: [LibraryWordGroup] = grouped.map { key, group in
            let sorted = group.sorted { $0.createdAt > $1.createdAt }
            return LibraryWordGroup(
                wordKey: key,
                word: sorted.first?.word ?? key,
                cardIDs: sorted.map(\.id)
            )
        }
        .sorted { lhs, rhs in
            lhs.word.localizedCaseInsensitiveCompare(rhs.word) == .orderedAscending
        }

        return (groups, [], false, index)
    }

    static func group(
        snapshots: [LibraryCardSnapshot],
        searchQuery: String
    ) -> [LibraryWordGroup] {
        buildListData(snapshots: snapshots, searchQuery: searchQuery).groups
    }
}

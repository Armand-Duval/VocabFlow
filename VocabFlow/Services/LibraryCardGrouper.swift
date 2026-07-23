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

enum LibraryCardGrouper {
    static let groupPageSize = 60

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

    static func group(
        snapshots: [LibraryCardSnapshot],
        searchQuery: String
    ) -> [LibraryWordGroup] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered: [LibraryCardSnapshot]
        if trimmed.isEmpty {
            filtered = snapshots
        } else {
            filtered = snapshots.filter { snapshot in
                snapshot.word.localizedCaseInsensitiveContains(trimmed)
                    || snapshot.sentence.localizedCaseInsensitiveContains(trimmed)
                    || snapshot.front.localizedCaseInsensitiveContains(trimmed)
                    || snapshot.back.localizedCaseInsensitiveContains(trimmed)
                    || (snapshot.contextNote?.localizedCaseInsensitiveContains(trimmed) ?? false)
                    || (snapshot.deckName?.localizedCaseInsensitiveContains(trimmed) ?? false)
            }
        }

        var grouped: [String: [LibraryCardSnapshot]] = [:]
        grouped.reserveCapacity(min(filtered.count, 4096))
        for snapshot in filtered {
            grouped[snapshot.wordKey, default: []].append(snapshot)
        }

        return grouped.map { key, group in
            let sorted = group.sorted { $0.createdAt > $1.createdAt }
            return LibraryWordGroup(
                wordKey: key,
                word: sorted.first?.word ?? key,
                cardIDs: sorted.map(\.id)
            )
        }
        .sorted { $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedAscending }
    }
}

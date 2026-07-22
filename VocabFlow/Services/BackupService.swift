import Foundation
import SwiftData

enum BackupService {
    static let defaultFilename = "vocabflow-backup"
    private static let currentVersion = 2

    @MainActor
    static func export(cards: [FlashCard], decks: [Deck]) throws -> Data {
        let referencedDeckIDs = Set(cards.compactMap { $0.deck?.id })
        let deckBackups = decks
            .filter { referencedDeckIDs.contains($0.id) }
            .map(DeckBackup.init(from:))

        let backup = FlashCardBackupFile(
            version: currentVersion,
            exportedAt: Date(),
            decks: deckBackups,
            cards: cards.map(FlashCardBackup.init(from:))
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }

    @MainActor
    static func importMerge(data: Data, into context: ModelContext) throws -> (added: Int, updated: Int) {
        let backup = try decode(data)
        let deckLookup = try importDecks(from: backup, into: context)
        let defaultDeck = DeckService.fetchOrCreateDefault(in: context)

        var added = 0
        var updated = 0

        for item in backup.cards {
            if let existing = try fetchCard(id: item.id, in: context) {
                item.apply(to: existing, deckLookup: deckLookup, defaultDeck: defaultDeck)
                updated += 1
            } else {
                context.insert(item.makeFlashCard(deckLookup: deckLookup, defaultDeck: defaultDeck))
                added += 1
            }
        }

        try context.save()
        return (added, updated)
    }

    @MainActor
    static func importReplace(data: Data, into context: ModelContext) throws -> Int {
        let existingCards = try context.fetch(FetchDescriptor<FlashCard>())
        existingCards.forEach { context.delete($0) }

        let existingDecks = try context.fetch(FetchDescriptor<Deck>())
        existingDecks
            .filter { $0.slug != DeckCatalog.defaultSlug }
            .forEach { context.delete($0) }

        let backup = try decode(data)
        let deckLookup = try importDecks(from: backup, into: context)
        let defaultDeck = DeckService.fetchOrCreateDefault(in: context)

        backup.cards.forEach {
            context.insert($0.makeFlashCard(deckLookup: deckLookup, defaultDeck: defaultDeck))
        }

        try context.save()
        return backup.cards.count
    }

    @MainActor
    private static func importDecks(
        from backup: FlashCardBackupFile,
        into context: ModelContext
    ) throws -> [UUID: Deck] {
        var lookup: [UUID: Deck] = [:]
        let defaultDeck = DeckService.fetchOrCreateDefault(in: context)
        lookup[defaultDeck.id] = defaultDeck

        guard let decks = backup.decks else { return lookup }

        for item in decks {
            if let existing = DeckService.fetchDeck(id: item.id, in: context) {
                lookup[item.id] = existing
                continue
            }
            if let slug = item.slug, let existing = DeckService.fetchDeck(slug: slug, in: context) {
                lookup[item.id] = existing
                continue
            }
            let deck = item.makeDeck()
            context.insert(deck)
            lookup[item.id] = deck
        }
        return lookup
    }

    private static func decode(_ data: Data) throws -> FlashCardBackupFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(FlashCardBackupFile.self, from: data)
    }

    private static func fetchCard(id: UUID, in context: ModelContext) throws -> FlashCard? {
        var descriptor = FetchDescriptor<FlashCard>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}

enum BackupDocumentSupport {
    static func readData(from url: URL) throws -> Data {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        return try Data(contentsOf: url)
    }
}

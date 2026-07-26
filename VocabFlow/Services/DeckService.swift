import Foundation
import SwiftData

enum DeckService {
    static let defaultDeckName = L10n.deckDefaultName
    private static let importYieldInterval = 40
    private static var didRunInitialBootstrap = false

    @MainActor
    static func refreshDecks(in context: ModelContext) -> [Deck] {
        bootstrap(in: context)
        context.processPendingChanges()
        var decks = fetchAll(in: context)
        if decks.isEmpty {
            let defaultDeck = fetchOrCreateDefault(in: context)
            context.processPendingChanges()
            decks = fetchAll(in: context)
            if decks.isEmpty {
                decks = [defaultDeck]
            }
        }
        return decks
    }

    @MainActor
    static func bootstrap(in context: ModelContext) {
        let defaultDeck = fetchOrCreateDefault(in: context)
        if !didRunInitialBootstrap {
            assignOrphanCards(to: defaultDeck, in: context)
            DeckCardCountService.recountAll(in: context)
            didRunInitialBootstrap = true
        }
        normalizeSelection(in: context, defaultDeck: defaultDeck)
        syncSharedCatalog(in: context)
    }

    @MainActor
    @discardableResult
    static func fetchOrCreateDefault(in context: ModelContext) -> Deck {
        if let existing = fetchDeck(slug: DeckCatalog.defaultSlug, in: context) {
            return existing
        }

        let deck = Deck(
            name: defaultDeckName,
            detailText: L10n.deckDefaultDetail,
            slug: DeckCatalog.defaultSlug,
            isBuiltIn: true,
            sortOrder: 0
        )
        context.insert(deck)
        do {
            try context.save()
        } catch {
            assertionFailure("Failed to create default deck: \(error)")
        }
        return deck
    }

    @MainActor
    static func fetchAll(in context: ModelContext) -> [Deck] {
        let descriptor = FetchDescriptor<Deck>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    @MainActor
    static func fetchDeck(id: UUID, in context: ModelContext) -> Deck? {
        var descriptor = FetchDescriptor<Deck>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    @MainActor
    static func fetchDeck(slug: String, in context: ModelContext) -> Deck? {
        fetchAll(in: context).first { $0.slug == slug }
    }

    @MainActor
    static func fetchDeck(name: String, in context: ModelContext) -> Deck? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return fetchAll(in: context).first { $0.name == trimmed }
    }

    @MainActor
    @discardableResult
    static func resolveOrCreateDeck(named name: String, in context: ModelContext) -> Deck {
        if let existing = fetchDeck(name: name, in: context) {
            return existing
        }
        return createCustomDeck(name: name, detailText: nil, in: context)
    }

    @MainActor
    static func resolvedDeck(id: UUID?, in context: ModelContext) -> Deck {
        if let id, let deck = fetchDeck(id: id, in: context) {
            return deck
        }
        return fetchOrCreateDefault(in: context)
    }

    @MainActor
    @discardableResult
    static func createCustomDeck(
        name: String,
        detailText: String?,
        in context: ModelContext
    ) -> Deck {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let deck = Deck(
            name: trimmed.isEmpty ? L10n.deckUntitled : trimmed,
            detailText: detailText?.trimmingCharacters(in: .whitespacesAndNewlines),
            slug: nil,
            isBuiltIn: false,
            sortOrder: nextSortOrder(in: context)
        )
        context.insert(deck)
        do {
            try context.save()
        } catch {
            assertionFailure("Failed to create deck: \(error)")
        }
        syncSharedCatalog(in: context)
        DeckCardCountService.notifyCatalogChanged()
        return deck
    }

    @MainActor
    static func importStarterCardsPublicAsync(
        from pack: DeckPackFile,
        into deck: Deck,
        context: ModelContext,
        progress: ImportProgressHandler? = nil
    ) async throws -> (deck: Deck, importedCards: Int) {
        try await importStarterCardsAsync(from: pack, into: deck, context: context, progress: progress)
    }

    @MainActor
    private static func importStarterCardsAsync(
        from pack: DeckPackFile,
        into deck: Deck,
        context: ModelContext,
        progress: ImportProgressHandler? = nil
    ) async throws -> (deck: Deck, importedCards: Int) {
        let total = pack.cards.count
        var imported = 0
        for (index, item) in pack.cards.enumerated() {
            context.insert(makeFlashCard(from: item, deck: deck))
            imported += 1
            progress?(imported, total)
            if index > 0, index % importYieldInterval == 0 {
                await Task.yield()
            }
        }
        DeckCardCountService.adjust(deck: deck, by: imported, in: context)
        try context.save()
        syncSharedCatalog(in: context)
        DeckCardCountService.notifyCatalogChanged()
        return (deck, imported)
    }

    @MainActor
    @discardableResult
    static func importPackAsync(
        _ pack: DeckPackFile,
        in context: ModelContext,
        markBuiltIn: Bool = false,
        progress: ImportProgressHandler? = nil
    ) async throws -> (deck: Deck, importedCards: Int) {
        let deck: Deck
        if let slug = pack.slug, let existing = fetchDeck(slug: slug, in: context) {
            deck = existing
        } else if let existing = fetchDeck(name: pack.name, in: context) {
            deck = existing
        } else {
            deck = Deck(
                name: pack.name,
                detailText: pack.detailText,
                slug: pack.slug,
                isBuiltIn: markBuiltIn,
                sortOrder: nextSortOrder(in: context)
            )
            context.insert(deck)
        }

        let total = pack.cards.count
        var imported = 0
        for (index, item) in pack.cards.enumerated() {
            context.insert(makeFlashCard(from: item, deck: deck))
            imported += 1
            progress?(imported, total)
            if index > 0, index % importYieldInterval == 0 {
                await Task.yield()
            }
        }

        DeckCardCountService.adjust(deck: deck, by: imported, in: context)
        try context.save()
        syncSharedCatalog(in: context)
        DeckCardCountService.notifyCatalogChanged()
        return (deck, imported)
    }

    @MainActor
    @discardableResult
    static func importPackIntoDeckAsync(
        _ pack: DeckPackFile,
        deck: Deck,
        in context: ModelContext,
        progress: ImportProgressHandler? = nil
    ) async throws -> Int {
        let total = pack.cards.count
        var imported = 0
        for (index, item) in pack.cards.enumerated() {
            context.insert(makeFlashCard(from: item, deck: deck))
            imported += 1
            progress?(imported, total)
            if index > 0, index % importYieldInterval == 0 {
                await Task.yield()
            }
        }

        DeckCardCountService.adjust(deck: deck, by: imported, in: context)
        try context.save()
        syncSharedCatalog(in: context)
        DeckCardCountService.notifyCatalogChanged()
        return imported
    }

    @MainActor
    @discardableResult
    static func importPack(
        _ pack: DeckPackFile,
        in context: ModelContext,
        markBuiltIn: Bool = false
    ) throws -> (deck: Deck, importedCards: Int) {
        let deck: Deck
        if let slug = pack.slug, let existing = fetchDeck(slug: slug, in: context) {
            deck = existing
        } else if let existing = fetchDeck(name: pack.name, in: context) {
            deck = existing
        } else {
            deck = Deck(
                name: pack.name,
                detailText: pack.detailText,
                slug: pack.slug,
                isBuiltIn: markBuiltIn,
                sortOrder: nextSortOrder(in: context)
            )
            context.insert(deck)
        }

        var imported = 0
        for item in pack.cards {
            context.insert(makeFlashCard(from: item, deck: deck))
            imported += 1
        }

        DeckCardCountService.adjust(deck: deck, by: imported, in: context)
        try context.save()
        syncSharedCatalog(in: context)
        DeckCardCountService.notifyCatalogChanged()
        return (deck, imported)
    }

    @MainActor
    static func importPackDataAsync(
        _ data: Data,
        in context: ModelContext,
        progress: ImportProgressHandler? = nil
    ) async throws -> (deck: Deck, importedCards: Int) {
        let pack = try JSONDecoder().decode(DeckPackFile.self, from: data)
        return try await importPackAsync(pack, in: context, progress: progress)
    }

    @MainActor
    static func importPackData(_ data: Data, in context: ModelContext) throws -> (deck: Deck, importedCards: Int) {
        let decoder = JSONDecoder()
        let pack = try decoder.decode(DeckPackFile.self, from: data)
        return try importPack(pack, in: context)
    }

    @MainActor
    static func deleteDeck(_ deck: Deck, in context: ModelContext) throws {
        guard deck.slug != DeckCatalog.defaultSlug else {
            throw DeckServiceError.cannotDeleteDefault
        }

        let defaultDeck = fetchOrCreateDefault(in: context)
        let movedCount = deck.cards.count
        deck.cards.forEach { $0.deck = defaultDeck }
        DeckCardCountService.adjust(deck: defaultDeck, by: movedCount, in: context)
        deck.cachedCardCount = 0
        context.delete(deck)
        try context.save()
        syncSharedCatalog(in: context)
        DeckCardCountService.notifyCatalogChanged()
    }

    @MainActor
    static func syncSharedCatalog(in context: ModelContext) {
        let entries = fetchAll(in: context).map {
            SharedDeckEntry(id: $0.id, name: $0.name, slug: $0.slug, sortOrder: $0.sortOrder)
        }
        SharedDeckStore.saveCatalog(entries)
    }

    @MainActor
    private static func assignOrphanCards(to defaultDeck: Deck, in context: ModelContext) {
        let descriptor = FetchDescriptor<FlashCard>()
        guard let cards = try? context.fetch(descriptor) else { return }
        var changed = false
        for card in cards where card.deck == nil {
            card.deck = defaultDeck
            changed = true
        }
        if changed {
            try? context.save()
            DeckCardCountService.recountAll(in: context)
        }
    }

    @MainActor
    private static func normalizeSelection(in context: ModelContext, defaultDeck: Deck) {
        if let selected = DeckSettings.lastSelectedDeckID,
           fetchDeck(id: selected, in: context) != nil {
            return
        }
        DeckSettings.lastSelectedDeckID = defaultDeck.id
    }

    @MainActor
    private static func nextSortOrder(in context: ModelContext) -> Int {
        let decks = fetchAll(in: context)
        return (decks.map(\.sortOrder).max() ?? 0) + 10
    }

    private static func makeFlashCard(from item: DeckPackCard, deck: Deck) -> FlashCard {
        FlashCard(
            word: item.word,
            sentence: item.sentence,
            cardType: CardType(rawValue: item.cardType ?? "") ?? .definition,
            front: item.front,
            back: item.back,
            contextNote: item.contextNote,
            phonetic: item.phonetic,
            deck: deck
        )
    }
}

enum DeckServiceError: LocalizedError {
    case cannotDeleteDefault

    var errorDescription: String? {
        switch self {
        case .cannotDeleteDefault:
            L10n.deckErrorCannotDeleteDefault
        }
    }
}

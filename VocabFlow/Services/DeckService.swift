import Foundation
import SwiftData

enum DeckService {
    static let defaultDeckName = L10n.deckDefaultName

    @MainActor
    static func bootstrap(in context: ModelContext) {
        let defaultDeck = fetchOrCreateDefault(in: context)
        assignOrphanCards(to: defaultDeck, in: context)
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
        try? context.save()
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
        var descriptor = FetchDescriptor<Deck>(predicate: #Predicate { $0.slug == slug })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
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
        try? context.save()
        syncSharedCatalog(in: context)
        return deck
    }

    @MainActor
    @discardableResult
    static func installPreset(
        slug: String,
        in context: ModelContext
    ) throws -> (deck: Deck, importedCards: Int) {
        if let existing = fetchDeck(slug: slug, in: context) {
            if existing.cards.isEmpty,
               let preset = DeckCatalog.preset(for: slug),
               let pack = DeckCatalog.loadBundledPack(named: preset.packFilename),
               !pack.cards.isEmpty {
                return try importStarterCards(from: pack, into: existing, context: context)
            }
            return (existing, 0)
        }

        guard let preset = DeckCatalog.preset(for: slug) else {
            throw DeckServiceError.unknownPreset
        }

        guard let pack = DeckCatalog.loadBundledPack(named: preset.packFilename) else {
            throw DeckServiceError.missingStarterPack
        }

        return try importPack(pack, in: context, markBuiltIn: true)
    }

    @MainActor
    static func importStarterCardsPublic(
        from pack: DeckPackFile,
        into deck: Deck,
        context: ModelContext
    ) throws -> (deck: Deck, importedCards: Int) {
        try importStarterCards(from: pack, into: deck, context: context)
    }

    @MainActor
    private static func importStarterCards(
        from pack: DeckPackFile,
        into deck: Deck,
        context: ModelContext
    ) throws -> (deck: Deck, importedCards: Int) {
        var imported = 0
        for item in pack.cards {
            let card = FlashCard(
                word: item.word,
                sentence: item.sentence,
                cardType: CardType(rawValue: item.cardType ?? "") ?? .definition,
                front: item.front,
                back: item.back,
                contextNote: item.contextNote,
                phonetic: item.phonetic,
                deck: deck
            )
            context.insert(card)
            imported += 1
        }
        try context.save()
        syncSharedCatalog(in: context)
        return (deck, imported)
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
            let card = FlashCard(
                word: item.word,
                sentence: item.sentence,
                cardType: CardType(rawValue: item.cardType ?? "") ?? .definition,
                front: item.front,
                back: item.back,
                contextNote: item.contextNote,
                phonetic: item.phonetic,
                deck: deck
            )
            context.insert(card)
            imported += 1
        }

        try context.save()
        syncSharedCatalog(in: context)
        return (deck, imported)
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
        deck.cards.forEach { $0.deck = defaultDeck }
        context.delete(deck)
        try context.save()
        syncSharedCatalog(in: context)
    }

    static func loadBundledPack(named filename: String) -> DeckPackFile? {
        DeckCatalog.loadBundledPack(named: filename)
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
        if changed { try? context.save() }
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
}

enum DeckServiceError: LocalizedError {
    case unknownPreset
    case cannotDeleteDefault
    case missingStarterPack

    var errorDescription: String? {
        switch self {
        case .unknownPreset:
            L10n.deckErrorUnknownPreset
        case .cannotDeleteDefault:
            L10n.deckErrorCannotDeleteDefault
        case .missingStarterPack:
            L10n.deckErrorMissingStarterPack
        }
    }
}

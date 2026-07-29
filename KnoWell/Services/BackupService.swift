import Foundation
import SwiftData

enum BackupService {
    static let defaultFilename = "knowell-backup"
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
        DeckCardCountService.recountAll(in: context)
        DeckCardCountService.notifyCatalogChanged()
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
        DeckCardCountService.recountAll(in: context)
        DeckCardCountService.notifyDataMaintenance()
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
            if let existing = DeckService.fetchDeck(name: item.name, in: context) {
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

    @MainActor
    static func export(checkedDeckIDs: Set<UUID>, cards: [FlashCard], decks: [Deck]) throws -> Data {
        let selectedDecks = decks.filter { checkedDeckIDs.contains($0.id) }
        let selectedCards = cards.filter { card in
            guard let deckID = card.deck?.id else { return false }
            return checkedDeckIDs.contains(deckID)
        }
        guard !selectedCards.isEmpty else { throw JSONImportError.emptyFile }
        return try export(cards: selectedCards, decks: selectedDecks)
    }

    @MainActor
    static func exportDeck(_ deck: Deck, cards: [FlashCard]) throws -> Data {
        let deckCards = cards.filter { $0.deck?.id == deck.id }
        guard !deckCards.isEmpty else { throw JSONImportError.emptyFile }
        return try export(cards: deckCards, decks: [deck])
    }

    struct JSONImportMergeResult {
        let added: Int
        let updated: Int
        let deckName: String?
        let targetDeckCount: Int

        var summaryMessage: String {
            if let deckName {
                if updated > 0 {
                    return L10n.deckImportDeckJSONResult(deckName, added: added, updated: updated)
                }
                return L10n.deckImportPackResult(deckName, count: added)
            }
            if targetDeckCount > 1 {
                return L10n.deckImportIntoSelectedDecksResult(
                    deckCount: targetDeckCount,
                    added: added,
                    updated: updated
                )
            }
            return L10n.importMergeResult(added: added, updated: updated)
        }
    }

    @MainActor
    static func importJSONMerge(
        data: Data,
        into context: ModelContext,
        targetDecks: [Deck]? = nil
    ) async throws -> JSONImportMergeResult {
        switch JSONImportSupport.detectKind(data) {
        case .deckPack:
            let result = try await DeckService.importPackDataAsync(data, in: context)
            return JSONImportMergeResult(
                added: result.importedCards,
                updated: 0,
                deckName: result.deck.name,
                targetDeckCount: 1
            )
        case .backup:
            if JSONImportSupport.hasDeckInfo(data) {
                let result = try importMerge(data: data, into: context)
                return JSONImportMergeResult(
                    added: result.added,
                    updated: result.updated,
                    deckName: nil,
                    targetDeckCount: 0
                )
            }
            guard let targetDecks, !targetDecks.isEmpty else {
                throw JSONImportError.needTargetDeckSelection
            }
            let result = try importBackupIntoSelectedDecks(
                data: data,
                targetDecks: targetDecks,
                into: context
            )
            return JSONImportMergeResult(
                added: result.added,
                updated: result.updated,
                deckName: targetDecks.count == 1 ? targetDecks[0].name : nil,
                targetDeckCount: targetDecks.count
            )
        case .unknown:
            throw JSONImportError.invalidJSON
        }
    }

    @MainActor
    private static func importBackupIntoSelectedDecks(
        data: Data,
        targetDecks: [Deck],
        into context: ModelContext
    ) throws -> (added: Int, updated: Int) {
        let backup = try decode(data)
        var added = 0
        var updated = 0

        if targetDecks.count == 1, let deck = targetDecks.first {
            let deckLookup = [deck.id: deck]
            for item in backup.cards {
                if let existing = try fetchCard(id: item.id, in: context) {
                    item.apply(to: existing, deckLookup: deckLookup, defaultDeck: deck)
                    updated += 1
                } else {
                    context.insert(item.makeFlashCard(deckLookup: deckLookup, defaultDeck: deck))
                    added += 1
                }
            }
        } else {
            for deck in targetDecks {
                let deckLookup = [deck.id: deck]
                for item in backup.cards {
                    let card = item.makeFlashCard(deckLookup: deckLookup, defaultDeck: deck)
                    card.id = UUID()
                    context.insert(card)
                    added += 1
                }
            }
        }

        try context.save()
        DeckCardCountService.recountAll(in: context)
        DeckCardCountService.notifyCatalogChanged()
        return (added, updated)
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
        try JSONImportSupport.readImportData(from: url)
    }
}

enum KnoWellJSONKind {
    case deckPack
    case backup
    case unknown
}

enum JSONImportSupport {
    static func detectKind(_ data: Data) -> KnoWellJSONKind {
        guard !data.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .unknown
        }
        if json["exportedAt"] != nil {
            return .backup
        }
        if json["name"] != nil, json["cards"] != nil {
            return .deckPack
        }
        return .unknown
    }

    static func hasDeckInfo(_ data: Data) -> Bool {
        switch detectKind(data) {
        case .deckPack:
            return true
        case .backup:
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let decks = json["decks"] as? [Any], !decks.isEmpty else {
                return false
            }
            return true
        case .unknown:
            return false
        }
    }

    static func readImportData(from url: URL) throws -> Data {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        var coordinationError: NSError?
        var readError: Error?
        var payload = Data()
        let coordinator = NSFileCoordinator()

        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { readableURL in
            do {
                if readableURL.pathExtension.lowercased() == "json",
                   (try? readableURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?
                    .ubiquitousItemDownloadingStatus == .notDownloaded {
                    try FileManager.default.startDownloadingUbiquitousItem(at: readableURL)
                }
                payload = try Data(contentsOf: readableURL)
            } catch {
                readError = error
            }
        }

        if let coordinationError { throw coordinationError }
        if let readError { throw readError }
        guard !payload.isEmpty else { throw JSONImportError.emptyFile }
        return payload
    }

    static func validate(_ data: Data, expecting kind: KnoWellJSONKind) throws {
        let detected = detectKind(data)
        switch (kind, detected) {
        case (.deckPack, .backup), (.backup, .deckPack):
            throw JSONImportError.wrongFormat(detected)
        case (_, .unknown):
            throw JSONImportError.invalidJSON
        default:
            return
        }
    }

    static func message(for error: Error, expecting kind: KnoWellJSONKind) -> String {
        if let importError = error as? JSONImportError {
            return importError.localizedDescription
        }
        if error is DecodingError {
            return wrongFormatHint(expecting: kind)
        }
        return error.localizedDescription
    }

    private static func wrongFormatHint(expecting kind: KnoWellJSONKind) -> String {
        switch kind {
        case .deckPack:
            return L10n.deckImportWrongFormatHintPack
        case .backup:
            return L10n.deckImportWrongFormatHintBackup
        case .unknown:
            return L10n.deckImportInvalidJSON
        }
    }
}

enum JSONImportError: LocalizedError {
    case emptyFile
    case invalidJSON
    case wrongFormat(KnoWellJSONKind)
    case needTargetDeckSelection

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            L10n.deckImportEmptyFile
        case .invalidJSON:
            L10n.deckImportInvalidJSON
        case .needTargetDeckSelection:
            L10n.deckImportNeedSelectionForNoDeckInfo
        case .wrongFormat(let kind):
            switch kind {
            case .backup:
                L10n.deckImportWrongFormatBackup
            case .deckPack:
                L10n.deckImportWrongFormatPack
            case .unknown:
                L10n.deckImportInvalidJSON
            }
        }
    }
}

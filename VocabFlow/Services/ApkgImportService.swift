import Foundation
import SQLite3
import SwiftData

enum ApkgImportError: LocalizedError {
    case invalidArchive
    case missingCollection
    case sqliteError(String)
    case emptyImport

    var errorDescription: String? {
        switch self {
        case .invalidArchive:
            L10n.apkgImportInvalid
        case .missingCollection:
            L10n.apkgImportMissingCollection
        case .sqliteError(let message):
            L10n.apkgImportFailed(message)
        case .emptyImport:
            L10n.apkgImportEmpty
        }
    }
}

enum ApkgImportService {
    struct ImportResult {
        let imported: Int
        let deckCount: Int
        let primaryDeckName: String?
        let targetDeckCount: Int

        var summaryMessage: String {
            if targetDeckCount > 1 {
                return L10n.deckImportIntoSelectedDecksResult(
                    deckCount: targetDeckCount,
                    added: imported,
                    updated: 0
                )
            }
            if deckCount <= 1, let primaryDeckName {
                return L10n.deckImportApkgResult(primaryDeckName, count: imported)
            }
            return L10n.deckImportApkgMultiResult(deckCount: deckCount, cardCount: imported)
        }
    }

    private static let importYieldInterval = 40
    fileprivate static let defaultDeckGroupKey: Int64 = -1

    static func hasDeckInfo(in data: Data) throws -> Bool {
        let groupedNotes = try parseGroupedNotes(from: data)
        return groupedNotes.contains { $0.deckName != nil }
    }

    private static func hasDeckInfo(in groupedNotes: [DeckNotesGroup]) -> Bool {
        groupedNotes.contains { $0.deckName != nil }
    }

    @MainActor
    static func importApkgAsync(
        data: Data,
        context: ModelContext,
        targetDecks: [Deck]? = nil,
        progress: ImportProgressHandler? = nil
    ) async throws -> ImportResult {
        let groupedNotes = try await Task.detached(priority: .userInitiated) {
            try parseGroupedNotes(from: data)
        }.value

        return try await importParsedGroups(
            groupedNotes,
            context: context,
            targetDecks: targetDecks,
            progress: progress
        )
    }

    @MainActor
    static func importApkg(
        data: Data,
        context: ModelContext,
        targetDecks: [Deck]? = nil
    ) throws -> ImportResult {
        let groupedNotes = try parseGroupedNotes(from: data)
        return try importParsedGroupsSync(
            groupedNotes,
            context: context,
            targetDecks: targetDecks
        )
    }

    @MainActor
    private static func importParsedGroups(
        _ groupedNotes: [DeckNotesGroup],
        context: ModelContext,
        targetDecks: [Deck]?,
        progress: ImportProgressHandler? = nil
    ) async throws -> ImportResult {
        guard !groupedNotes.isEmpty else { throw ApkgImportError.emptyImport }

        let mappedGroups = groupedNotes.filter { $0.deckName != nil }
        let unmappedNotes = groupedNotes.filter { $0.deckName == nil }.flatMap(\.notes)

        if mappedGroups.isEmpty, unmappedNotes.isEmpty {
            throw ApkgImportError.emptyImport
        }

        var imported = 0
        var primaryDeckName: String?
        var deckCount = 0
        var targetDeckCount = 0

        if !mappedGroups.isEmpty {
            let result = try await importGroupedNotes(
                mappedGroups,
                context: context,
                progress: progress,
                targetDeckCount: 0
            )
            imported += result.imported
            primaryDeckName = result.primaryDeckName
            deckCount = result.deckCount
        }

        if !unmappedNotes.isEmpty {
            guard let targetDecks, !targetDecks.isEmpty else {
                throw JSONImportError.needTargetDeckSelection
            }
            let fallbackGroup = [DeckNotesGroup(deckName: nil, notes: unmappedNotes)]
            let result = try await importNotesIntoSelectedDecks(
                groupedNotes: fallbackGroup,
                targetDecks: targetDecks,
                context: context,
                progress: progress
            )
            imported += result.imported
            targetDeckCount = result.targetDeckCount
            if primaryDeckName == nil {
                primaryDeckName = result.primaryDeckName
            }
        }

        DeckCardCountService.recountAll(in: context)
        DeckCardCountService.notifyCatalogChanged()

        return ImportResult(
            imported: imported,
            deckCount: deckCount,
            primaryDeckName: primaryDeckName,
            targetDeckCount: targetDeckCount
        )
    }

    @MainActor
    private static func importParsedGroupsSync(
        _ groupedNotes: [DeckNotesGroup],
        context: ModelContext,
        targetDecks: [Deck]?
    ) throws -> ImportResult {
        guard !groupedNotes.isEmpty else { throw ApkgImportError.emptyImport }

        let mappedGroups = groupedNotes.filter { $0.deckName != nil }
        let unmappedNotes = groupedNotes.filter { $0.deckName == nil }.flatMap(\.notes)

        if mappedGroups.isEmpty, unmappedNotes.isEmpty {
            throw ApkgImportError.emptyImport
        }

        var imported = 0
        var primaryDeckName: String?
        var deckCount = 0
        var targetDeckCount = 0

        if !mappedGroups.isEmpty {
            let result = try importGroupedNotesSync(
                mappedGroups,
                context: context,
                targetDeckCount: 0
            )
            imported += result.imported
            primaryDeckName = result.primaryDeckName
            deckCount = result.deckCount
        }

        if !unmappedNotes.isEmpty {
            guard let targetDecks, !targetDecks.isEmpty else {
                throw JSONImportError.needTargetDeckSelection
            }
            let fallbackGroup = [DeckNotesGroup(deckName: nil, notes: unmappedNotes)]
            let result = try importNotesIntoSelectedDecksSync(
                groupedNotes: fallbackGroup,
                targetDecks: targetDecks,
                context: context
            )
            imported += result.imported
            targetDeckCount = result.targetDeckCount
            if primaryDeckName == nil {
                primaryDeckName = result.primaryDeckName
            }
        }

        DeckCardCountService.recountAll(in: context)
        DeckCardCountService.notifyCatalogChanged()

        return ImportResult(
            imported: imported,
            deckCount: deckCount,
            primaryDeckName: primaryDeckName,
            targetDeckCount: targetDeckCount
        )
    }

    @MainActor
    private static func importNotesIntoSelectedDecks(
        groupedNotes: [DeckNotesGroup],
        targetDecks: [Deck],
        context: ModelContext,
        progress: ImportProgressHandler? = nil
    ) async throws -> ImportResult {
        let notes = groupedNotes.flatMap(\.notes)
        guard !notes.isEmpty else { throw ApkgImportError.emptyImport }

        let total = notes.count * targetDecks.count
        var imported = 0

        for deck in targetDecks {
            for note in notes {
                context.insert(makeFlashCard(from: note, deck: deck))
                imported += 1
                progress?(imported, total)
                if imported > 0, imported % importYieldInterval == 0 {
                    await Task.yield()
                }
            }
            DeckCardCountService.adjust(deck: deck, by: notes.count, in: context)
        }

        try context.save()
        DeckCardCountService.notifyCatalogChanged()
        return ImportResult(
            imported: imported,
            deckCount: targetDecks.count,
            primaryDeckName: targetDecks.first?.name,
            targetDeckCount: targetDecks.count
        )
    }

    @MainActor
    private static func importNotesIntoSelectedDecksSync(
        groupedNotes: [DeckNotesGroup],
        targetDecks: [Deck],
        context: ModelContext
    ) throws -> ImportResult {
        let notes = groupedNotes.flatMap(\.notes)
        guard !notes.isEmpty else { throw ApkgImportError.emptyImport }

        var imported = 0
        for deck in targetDecks {
            for note in notes {
                context.insert(makeFlashCard(from: note, deck: deck))
                imported += 1
            }
            DeckCardCountService.adjust(deck: deck, by: notes.count, in: context)
        }

        try context.save()
        DeckCardCountService.notifyCatalogChanged()
        return ImportResult(
            imported: imported,
            deckCount: targetDecks.count,
            primaryDeckName: targetDecks.first?.name,
            targetDeckCount: targetDecks.count
        )
    }

    @MainActor
    private static func importGroupedNotes(
        _ groupedNotes: [DeckNotesGroup],
        context: ModelContext,
        progress: ImportProgressHandler? = nil,
        targetDeckCount: Int
    ) async throws -> ImportResult {
        let total = groupedNotes.reduce(0) { $0 + $1.notes.count }
        var imported = 0
        var primaryDeckName: String?

        for (index, group) in groupedNotes.enumerated() {
            guard let deckName = group.deckName else { continue }
            let deck = DeckService.resolveOrCreateDeck(named: deckName, in: context)
            if index == 0 {
                primaryDeckName = deck.name
            }

            for note in group.notes {
                context.insert(makeFlashCard(from: note, deck: deck))
                imported += 1
                progress?(imported, total)
                if imported > 0, imported % importYieldInterval == 0 {
                    await Task.yield()
                }
            }

            DeckCardCountService.adjust(deck: deck, by: group.notes.count, in: context)
        }

        try context.save()
        DeckCardCountService.notifyCatalogChanged()
        return ImportResult(
            imported: imported,
            deckCount: groupedNotes.count,
            primaryDeckName: primaryDeckName,
            targetDeckCount: targetDeckCount
        )
    }

    @MainActor
    private static func importGroupedNotesSync(
        _ groupedNotes: [DeckNotesGroup],
        context: ModelContext,
        targetDeckCount: Int
    ) throws -> ImportResult {
        var imported = 0
        var primaryDeckName: String?

        for (index, group) in groupedNotes.enumerated() {
            guard let deckName = group.deckName else { continue }
            let deck = DeckService.resolveOrCreateDeck(named: deckName, in: context)
            if index == 0 {
                primaryDeckName = deck.name
            }

            for note in group.notes {
                context.insert(makeFlashCard(from: note, deck: deck))
                imported += 1
            }

            DeckCardCountService.adjust(deck: deck, by: group.notes.count, in: context)
        }

        try context.save()
        DeckCardCountService.notifyCatalogChanged()
        return ImportResult(
            imported: imported,
            deckCount: groupedNotes.count,
            primaryDeckName: primaryDeckName,
            targetDeckCount: targetDeckCount
        )
    }

    private static func makeFlashCard(from note: ImportedNote, deck: Deck) -> FlashCard {
        FlashCard(
            word: note.word,
            sentence: note.sentence,
            cardType: .definition,
            front: note.front,
            back: note.back,
            deck: deck
        )
    }

    private struct DeckNotesGroup {
        let deckName: String?
        let notes: [ImportedNote]
    }

    private static func parseGroupedNotes(from data: Data) throws -> [DeckNotesGroup] {
        guard let collectionData = extractCollection(from: data) else {
            throw ApkgImportError.missingCollection
        }
        return try readGroupedNotes(from: collectionData)
    }

    private static func extractCollection(from data: Data) -> Data? {
        if let direct = MinimalZipReader.data(forEntryNamed: "collection.anki2", in: data) {
            return direct
        }
        if let direct21 = MinimalZipReader.data(forEntryNamed: "collection.anki21", in: data) {
            return direct21
        }
        return MinimalZipReader.firstEntry(where: { $0.contains("collection.anki") }, in: data)?.data
    }

    private static func readGroupedNotes(from sqliteData: Data) throws -> [DeckNotesGroup] {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vocabflow-import-\(UUID().uuidString).anki2")
        try sqliteData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        var db: OpaquePointer?
        guard sqlite3_open(tempURL.path, &db) == SQLITE_OK, let db else {
            throw ApkgImportError.sqliteError("open failed")
        }
        defer { sqlite3_close(db) }

        let deckNames = try readDeckNames(from: db)
        let grouped = try readNotesGroupedByDeck(from: db, deckNames: deckNames)
        return grouped
            .sorted { $0.key.sortKey < $1.key.sortKey }
            .map { DeckNotesGroup(deckName: $0.value.name, notes: $0.value.notes) }
            .filter { !$0.notes.isEmpty }
    }

    private static func readDeckNames(from db: OpaquePointer) throws -> [Int64: String] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT decks FROM col LIMIT 1", -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw ApkgImportError.sqliteError("prepare col failed")
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW,
              let decksCString = sqlite3_column_text(statement, 0) else {
            return [:]
        }

        let decksJSON = String(cString: decksCString)
        guard let data = decksJSON.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }

        var names: [Int64: String] = [:]
        for (key, value) in root {
            guard let deckObject = value as? [String: Any],
                  let name = deckObject["name"] as? String else {
                continue
            }
            if let deckID = Int64(key) {
                names[deckID] = name
            }
            if let objectID = deckObject["id"] as? Int64 {
                names[objectID] = name
            } else if let objectID = deckObject["id"] as? Int {
                names[Int64(objectID)] = name
            }
        }

        if names.isEmpty {
            names = try readDeckNamesFromTable(from: db)
        }
        return names
    }

    private static func readDeckNamesFromTable(from db: OpaquePointer) throws -> [Int64: String] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT id, name FROM decks", -1, &statement, nil) == SQLITE_OK,
              let statement else {
            return [:]
        }
        defer { sqlite3_finalize(statement) }

        var names: [Int64: String] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            let deckID = sqlite3_column_int64(statement, 0)
            guard let nameCString = sqlite3_column_text(statement, 1) else { continue }
            names[deckID] = String(cString: nameCString)
        }
        return names
    }

    private static func readNotesGroupedByDeck(
        from db: OpaquePointer,
        deckNames: [Int64: String]
    ) throws -> [Int64: (name: String?, notes: [ImportedNote])] {
        var statement: OpaquePointer?
        let sql = """
        SELECT CASE WHEN cards.odid != 0 THEN cards.odid ELSE cards.did END,
               notes.flds, notes.tags
        FROM cards
        JOIN notes ON cards.nid = notes.id
        ORDER BY 1, cards.id
        """
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ApkgImportError.sqliteError("prepare cards failed")
        }
        defer { sqlite3_finalize(statement) }

        var grouped: [Int64: (name: String?, notes: [ImportedNote])] = [:]

        while sqlite3_step(statement) == SQLITE_ROW {
            let deckID = sqlite3_column_int64(statement, 0)
            guard let fldsCString = sqlite3_column_text(statement, 1) else { continue }
            let flds = String(cString: fldsCString)
            let tags = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
            guard let note = ImportedNote(flds: flds, tags: tags) else { continue }

            let resolvedName = deckNames[deckID]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            let groupKey = resolvedName == nil ? defaultDeckGroupKey : deckID
            var entry = grouped[groupKey] ?? (resolvedName, [])
            entry.notes.append(note)
            grouped[groupKey] = entry
        }

        return grouped
    }
}

private extension Int64 {
    var sortKey: Int64 {
        self == ApkgImportService.defaultDeckGroupKey ? Int64.max : self
    }
}

private struct ImportedNote {
    let word: String
    let sentence: String
    let front: String
    let back: String

    init?(flds: String, tags: String) {
        let parts = flds.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
        guard let rawFront = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines), !rawFront.isEmpty else {
            return nil
        }

        front = rawFront
        back = parts.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if back.isEmpty {
            return nil
        }

        let tagWord = tags
            .split(whereSeparator: \.isWhitespace)
            .map { String($0) }
            .first?
            .replacingOccurrences(of: "_", with: " ")
        word = tagWord ?? rawFront.components(separatedBy: .newlines).first ?? rawFront
        sentence = rawFront
    }
}

private extension String {
    var nilIfEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}

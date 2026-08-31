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
        let unmappedCount: Int
        let incompleteCount: Int
        let unmappedDeckName: String?
        let incompleteDeckName: String?

        var summaryMessage: String {
            var parts: [String] = []
            let mappedCount = imported - unmappedCount - incompleteCount

            if mappedCount > 0 {
                if deckCount <= 1, let primaryDeckName {
                    parts.append(L10n.deckImportApkgResult(primaryDeckName, count: mappedCount))
                } else {
                    parts.append(L10n.deckImportApkgMultiResult(deckCount: deckCount, cardCount: mappedCount))
                }
            }

            if unmappedCount > 0, let unmappedDeckName {
                parts.append(L10n.deckImportApkgUnmappedResult(unmappedDeckName, count: unmappedCount))
            }

            if incompleteCount > 0, let incompleteDeckName {
                parts.append(L10n.deckImportApkgIncompleteResult(incompleteDeckName, count: incompleteCount))
            }

            if parts.isEmpty {
                return L10n.deckImportApkgMultiResult(deckCount: max(deckCount, 1), cardCount: imported)
            }
            return parts.joined(separator: "\n")
        }
    }

    private static let importYieldInterval = 40

    static func hasDeckInfo(in data: Data) throws -> Bool {
        let parsed = try parseImport(from: data)
        return !parsed.mappedGroups.isEmpty
    }

    @MainActor
    static func importApkgAsync(
        data: Data,
        context: ModelContext,
        progress: ImportProgressHandler? = nil
    ) async throws -> ImportResult {
        let parsed = try await Task.detached(priority: .userInitiated) {
            try parseImport(from: data)
        }.value

        return try await importParsed(
            parsed,
            context: context,
            progress: progress
        )
    }

    @MainActor
    static func importApkg(
        data: Data,
        context: ModelContext
    ) throws -> ImportResult {
        let parsed = try parseImport(from: data)
        return try importParsedSync(parsed, context: context)
    }

    @MainActor
    private static func importParsed(
        _ parsed: ParsedApkgImport,
        context: ModelContext,
        progress: ImportProgressHandler? = nil
    ) async throws -> ImportResult {
        guard !parsed.isEmpty else { throw ApkgImportError.emptyImport }

        let previousAutosave = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = previousAutosave }

        var imported = 0
        var primaryDeckName: String?
        var deckCount = 0
        var unmappedDeckName: String?
        var incompleteDeckName: String?

        if !parsed.mappedGroups.isEmpty {
            let groups = parsed.mappedGroups.map { DeckNotesGroup(deckName: $0.deckName, notes: $0.notes) }
            let result = try await importGroupedNotes(
                groups,
                context: context,
                progress: progress
            )
            imported += result.imported
            primaryDeckName = result.primaryDeckName
            deckCount = result.deckCount
        }

        if !parsed.unmappedNotes.isEmpty {
            unmappedDeckName = L10n.deckImportFallbackUnmappedName
            let deck = DeckService.resolveOrCreateDeck(named: unmappedDeckName!, in: context)
            let count = try await importNotes(
                parsed.unmappedNotes,
                into: deck,
                context: context,
                progress: progress
            )
            imported += count
            if primaryDeckName == nil { primaryDeckName = deck.name }
            deckCount += 1
        }

        if !parsed.incompleteNotes.isEmpty {
            incompleteDeckName = L10n.deckImportFallbackIncompleteName
            let deck = DeckService.resolveOrCreateDeck(named: incompleteDeckName!, in: context)
            let count = try await importNotes(
                parsed.incompleteNotes,
                into: deck,
                context: context,
                progress: progress
            )
            imported += count
            if primaryDeckName == nil { primaryDeckName = deck.name }
            deckCount += 1
        }

        DeckCardCountService.recountAll(in: context)
        DeckCardCountService.notifyCatalogChanged()

        return ImportResult(
            imported: imported,
            deckCount: deckCount,
            primaryDeckName: primaryDeckName,
            unmappedCount: parsed.unmappedNotes.count,
            incompleteCount: parsed.incompleteNotes.count,
            unmappedDeckName: unmappedDeckName,
            incompleteDeckName: incompleteDeckName
        )
    }

    @MainActor
    private static func importParsedSync(
        _ parsed: ParsedApkgImport,
        context: ModelContext
    ) throws -> ImportResult {
        guard !parsed.isEmpty else { throw ApkgImportError.emptyImport }

        let previousAutosave = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = previousAutosave }

        var imported = 0
        var primaryDeckName: String?
        var deckCount = 0
        var unmappedDeckName: String?
        var incompleteDeckName: String?

        if !parsed.mappedGroups.isEmpty {
            let groups = parsed.mappedGroups.map { DeckNotesGroup(deckName: $0.deckName, notes: $0.notes) }
            let result = try importGroupedNotesSync(groups, context: context)
            imported += result.imported
            primaryDeckName = result.primaryDeckName
            deckCount = result.deckCount
        }

        if !parsed.unmappedNotes.isEmpty {
            unmappedDeckName = L10n.deckImportFallbackUnmappedName
            let deck = DeckService.resolveOrCreateDeck(named: unmappedDeckName!, in: context)
            imported += try importNotesSync(parsed.unmappedNotes, into: deck, context: context)
            if primaryDeckName == nil { primaryDeckName = deck.name }
            deckCount += 1
        }

        if !parsed.incompleteNotes.isEmpty {
            incompleteDeckName = L10n.deckImportFallbackIncompleteName
            let deck = DeckService.resolveOrCreateDeck(named: incompleteDeckName!, in: context)
            imported += try importNotesSync(parsed.incompleteNotes, into: deck, context: context)
            if primaryDeckName == nil { primaryDeckName = deck.name }
            deckCount += 1
        }

        DeckCardCountService.recountAll(in: context)
        DeckCardCountService.notifyCatalogChanged()

        return ImportResult(
            imported: imported,
            deckCount: deckCount,
            primaryDeckName: primaryDeckName,
            unmappedCount: parsed.unmappedNotes.count,
            incompleteCount: parsed.incompleteNotes.count,
            unmappedDeckName: unmappedDeckName,
            incompleteDeckName: incompleteDeckName
        )
    }

    @MainActor
    private static func importNotes(
        _ notes: [ImportedNote],
        into deck: Deck,
        context: ModelContext,
        progress: ImportProgressHandler? = nil
    ) async throws -> Int {
        guard !notes.isEmpty else { return 0 }

        var imported = 0
        for note in notes {
            context.insert(makeFlashCard(from: note, deck: deck))
            imported += 1
            progress?(imported, notes.count)
            if imported > 0, imported % importYieldInterval == 0 {
                await Task.yield()
            }
        }
        DeckCardCountService.adjust(deck: deck, by: notes.count, in: context)
        try context.save()
        return imported
    }

    @MainActor
    private static func importNotesSync(
        _ notes: [ImportedNote],
        into deck: Deck,
        context: ModelContext
    ) throws -> Int {
        guard !notes.isEmpty else { return 0 }

        for note in notes {
            context.insert(makeFlashCard(from: note, deck: deck))
        }
        DeckCardCountService.adjust(deck: deck, by: notes.count, in: context)
        try context.save()
        return notes.count
    }

    private struct GroupImportResult {
        let imported: Int
        let deckCount: Int
        let primaryDeckName: String?
    }

    private struct ParsedApkgImport {
        var mappedGroups: [(deckName: String, notes: [ImportedNote])]
        var unmappedNotes: [ImportedNote]
        var incompleteNotes: [ImportedNote]

        var isEmpty: Bool {
            mappedGroups.allSatisfy { $0.notes.isEmpty }
                && unmappedNotes.isEmpty
                && incompleteNotes.isEmpty
        }
    }

    @MainActor
    private static func importGroupedNotes(
        _ groupedNotes: [DeckNotesGroup],
        context: ModelContext,
        progress: ImportProgressHandler? = nil
    ) async throws -> GroupImportResult {
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
        return GroupImportResult(
            imported: imported,
            deckCount: groupedNotes.count,
            primaryDeckName: primaryDeckName
        )
    }

    @MainActor
    private static func importGroupedNotesSync(
        _ groupedNotes: [DeckNotesGroup],
        context: ModelContext
    ) throws -> GroupImportResult {
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
        return GroupImportResult(
            imported: imported,
            deckCount: groupedNotes.count,
            primaryDeckName: primaryDeckName
        )
    }

    private static func makeFlashCard(from note: ImportedNote, deck: Deck) -> FlashCard {
        if let backup = note.backup {
            let card = backup.makeFlashCard(deckLookup: [:], defaultDeck: deck)
            card.id = UUID()
            card.deck = deck
            return card
        }
        return FlashCard(
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

    private static func parseImport(from data: Data) throws -> ParsedApkgImport {
        guard let collectionData = extractCollection(from: data) else {
            throw ApkgImportError.missingCollection
        }
        return try readParsedImport(from: collectionData)
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

    private static func readParsedImport(from sqliteData: Data) throws -> ParsedApkgImport {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("knowell-import-\(UUID().uuidString).anki2")
        try sqliteData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        var db: OpaquePointer?
        guard sqlite3_open(tempURL.path, &db) == SQLITE_OK, let db else {
            throw ApkgImportError.sqliteError("open failed")
        }
        defer { sqlite3_close(db) }

        let deckNames = try readDeckNames(from: db)
        return try readParsedImport(from: db, deckNames: deckNames)
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
        guard let root = parseDeckDictionary(from: decksJSON) else {
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

    /// Valid Anki JSON, plus the broken concatenated objects older KnoWell exports wrote.
    static func parseDeckDictionary(from raw: String) -> [String: Any]? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return root
        }
        let wrapped = "[" + trimmed.replacingOccurrences(of: "}{", with: "},{") + "]"
        guard let wrappedData = wrapped.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: wrappedData) as? [[String: Any]] else {
            return nil
        }
        var merged: [String: Any] = [:]
        for item in array {
            for (key, value) in item {
                merged[key] = value
            }
        }
        return merged.isEmpty ? nil : merged
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

    private static func readParsedImport(
        from db: OpaquePointer,
        deckNames: [Int64: String]
    ) throws -> ParsedApkgImport {
        var statement: OpaquePointer?
        let sql = """
        SELECT CASE WHEN cards.odid != 0 THEN cards.odid ELSE cards.did END,
               notes.flds, notes.tags, notes.data
        FROM cards
        JOIN notes ON cards.nid = notes.id
        ORDER BY 1, cards.id
        """
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ApkgImportError.sqliteError("prepare cards failed")
        }
        defer { sqlite3_finalize(statement) }

        var mappedByName: [String: [ImportedNote]] = [:]
        var mappedOrder: [String] = []
        var unmappedNotes: [ImportedNote] = []
        var incompleteNotes: [ImportedNote] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            let deckID = sqlite3_column_int64(statement, 0)
            guard let fldsCString = sqlite3_column_text(statement, 1) else { continue }
            let flds = String(cString: fldsCString)
            let tags = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
            let dataJSON = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
            let parsed = ImportedNote.parse(flds: flds, tags: tags, dataJSON: dataJSON)

            if !parsed.isComplete {
                incompleteNotes.append(parsed.note)
                continue
            }

            let resolvedName = deckNames[deckID]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            if let resolvedName {
                if mappedByName[resolvedName] == nil {
                    mappedOrder.append(resolvedName)
                }
                mappedByName[resolvedName, default: []].append(parsed.note)
            } else {
                unmappedNotes.append(parsed.note)
            }
        }

        let mappedGroups = mappedOrder.compactMap { name -> (deckName: String, notes: [ImportedNote])? in
            guard let notes = mappedByName[name], !notes.isEmpty else { return nil }
            return (deckName: name, notes: notes)
        }

        return ParsedApkgImport(
            mappedGroups: mappedGroups,
            unmappedNotes: unmappedNotes,
            incompleteNotes: incompleteNotes
        )
    }
}

private struct ParsedImportedNote {
    let note: ImportedNote
    let isComplete: Bool
}

private struct ImportedNote {
    let word: String
    let sentence: String
    let front: String
    let back: String
    let backup: FlashCardBackup?

    static func parse(flds: String, tags: String, dataJSON: String = "") -> ParsedImportedNote {
        if let backup = decodeKnowellBackup(from: dataJSON) {
            let note = ImportedNote(
                word: backup.word,
                sentence: backup.sentence,
                front: backup.front,
                back: backup.back,
                backup: backup
            )
            let complete = !backup.word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !backup.front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return ParsedImportedNote(note: note, isComplete: complete)
        }

        let parts = flds
            .split(separator: "\u{1f}", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let tagWord = tags
            .split(whereSeparator: \.isWhitespace)
            .map { String($0) }
            .first?
            .replacingOccurrences(of: "_", with: " ")

        let nonEmptyParts = parts.filter { !$0.isEmpty }
        if nonEmptyParts.isEmpty {
            let fallback = tagWord ?? L10n.deckImportEmptyCardPlaceholder
            let note = ImportedNote(
                word: fallback,
                sentence: fallback,
                front: fallback,
                back: L10n.deckImportMissingBackPlaceholder,
                backup: nil
            )
            return ParsedImportedNote(note: note, isComplete: false)
        }

        let front = nonEmptyParts[0]
        let back = nonEmptyParts.dropFirst().joined(separator: "\n")
        let isComplete = !back.isEmpty
        let resolvedBack = back.isEmpty ? L10n.deckImportMissingBackPlaceholder : back
        let word = tagWord ?? front.components(separatedBy: .newlines).first ?? front

        let note = ImportedNote(
            word: word,
            sentence: front,
            front: front,
            back: resolvedBack,
            backup: nil
        )
        return ParsedImportedNote(note: note, isComplete: isComplete)
    }

    private static func decodeKnowellBackup(from dataJSON: String) -> FlashCardBackup? {
        let trimmed = dataJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "{}", let data = trimmed.data(using: .utf8) else {
            return nil
        }
        struct Wrapper: Decodable {
            let knowell: FlashCardBackup
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Wrapper.self, from: data).knowell
    }
}

private extension String {
    var nilIfEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}

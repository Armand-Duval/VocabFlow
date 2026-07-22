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
    }

    @MainActor
    static func importApkg(
        data: Data,
        into deck: Deck,
        context: ModelContext
    ) throws -> ImportResult {
        guard let collectionData = extractCollection(from: data) else {
            throw ApkgImportError.missingCollection
        }

        let notes = try readNotes(from: collectionData)
        guard !notes.isEmpty else { throw ApkgImportError.emptyImport }

        for note in notes {
            let card = FlashCard(
                word: note.word,
                sentence: note.sentence,
                cardType: .definition,
                front: note.front,
                back: note.back,
                deck: deck
            )
            context.insert(card)
        }

        try context.save()
        return ImportResult(imported: notes.count)
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

    private static func readNotes(from sqliteData: Data) throws -> [ImportedNote] {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vocabflow-import-\(UUID().uuidString).anki2")
        try sqliteData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        var db: OpaquePointer?
        guard sqlite3_open(tempURL.path, &db) == SQLITE_OK, let db else {
            throw ApkgImportError.sqliteError("open failed")
        }
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        let sql = "SELECT flds, tags FROM notes"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ApkgImportError.sqliteError("prepare failed")
        }
        defer { sqlite3_finalize(statement) }

        var notes: [ImportedNote] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let fldsCString = sqlite3_column_text(statement, 0) else { continue }
            let flds = String(cString: fldsCString)
            let tags = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            if let note = ImportedNote(flds: flds, tags: tags) {
                notes.append(note)
            }
        }
        return notes
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

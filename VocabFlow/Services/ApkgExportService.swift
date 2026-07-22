import Foundation
import SQLite3

enum ApkgExportError: LocalizedError {
    case emptyDeck
    case sqliteError(String)
    case zipFailed

    var errorDescription: String? {
        switch self {
        case .emptyDeck:
            L10n.apkgExportEmpty
        case .sqliteError(let message):
            L10n.apkgExportFailed(message)
        case .zipFailed:
            L10n.apkgExportFailed(L10n.apkgExportZipFailed)
        }
    }
}

enum ApkgExportService {
    static let defaultFilename = "vocabflow"
    private static let deckID: Int64 = 1
    private static let modelID: Int64 = 1_607_392_319
    private static let deckName = "VocabFlow"

    static func export(cards: [FlashCard]) throws -> Data {
        guard !cards.isEmpty else { throw ApkgExportError.emptyDeck }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vocabflow-apkg-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dbURL = tempDir.appendingPathComponent("collection.anki2")
        try buildCollection(at: dbURL, cards: cards)

        let mediaData = Data("{}".utf8)
        var zipWriter = MinimalZipWriter()
        zipWriter.addEntry(name: "collection.anki2", data: try Data(contentsOf: dbURL))
        zipWriter.addEntry(name: "media", data: mediaData)
        return zipWriter.build()
    }

    private static func buildCollection(at url: URL, cards: [FlashCard]) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else {
            throw ApkgExportError.sqliteError("open failed")
        }
        defer { sqlite3_close(db) }

        try exec(db, """
        CREATE TABLE col (
            id integer PRIMARY KEY,
            crt integer NOT NULL,
            mod integer NOT NULL,
            scm integer NOT NULL,
            ver integer NOT NULL,
            dty integer NOT NULL,
            usn integer NOT NULL,
            ls integer NOT NULL,
            conf text NOT NULL,
            models text NOT NULL,
            decks text NOT NULL,
            dconf text NOT NULL,
            tags text NOT NULL
        );
        CREATE TABLE notes (
            id integer PRIMARY KEY,
            guid text NOT NULL,
            mid integer NOT NULL,
            mod integer NOT NULL,
            usn integer NOT NULL,
            tags text NOT NULL,
            flds text NOT NULL,
            sfld integer NOT NULL,
            csum integer NOT NULL,
            flags integer NOT NULL,
            data text NOT NULL
        );
        CREATE TABLE cards (
            id integer PRIMARY KEY,
            nid integer NOT NULL,
            did integer NOT NULL,
            ord integer NOT NULL,
            mod integer NOT NULL,
            usn integer NOT NULL,
            type integer NOT NULL,
            queue integer NOT NULL,
            due integer NOT NULL,
            ivl integer NOT NULL,
            factor integer NOT NULL,
            reps integer NOT NULL,
            lapses integer NOT NULL,
            left integer NOT NULL,
            odue integer NOT NULL,
            odid integer NOT NULL,
            flags integer NOT NULL,
            data text NOT NULL
        );
        CREATE TABLE revlog (
            id integer PRIMARY KEY,
            cid integer NOT NULL,
            usn integer NOT NULL,
            ease integer NOT NULL,
            ivl integer NOT NULL,
            lastIvl integer NOT NULL,
            factor integer NOT NULL,
            time integer NOT NULL,
            type integer NOT NULL
        );
        CREATE TABLE graves (
            usn integer NOT NULL,
            oid integer NOT NULL,
            type integer NOT NULL
        );
        """)

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let conf = """
        {"activeDecks":[\(deckID)],"curDeck":\(deckID),"newSpread":0,"collapseTime":1200,"timeLim":0,"estTimes":true,"sortType":"noteFld","sortBackwards":false,"addToCur":true,"dayLearnFirst":false,"schedVer":2}
        """
        let models = basicModelJSON()
        let decks = """
        {"\(deckID)":{"id":\(deckID),"mod":0,"name":"\(deckName)","usn":0,"desc":"","dyn":0,"conf":1,"extConf":{},"collapsed":false}}
        """
        let dconf = """
        {"1":{"id":1,"mod":0,"name":"Default","usn":0,"maxTaken":60,"autoplay":true,"timer":0,"replayq":true,"new":{"bury":false,"delays":[1,10],"initialFactor":2500,"ints":[1,4,7],"order":1,"perDay":20},"rev":{"bury":false,"ease4":1.3,"fuzz":0.05,"ivlFct":1,"maxIvl":36500,"perDay":200,"hardFactor":1.2},"lapse":{"delays":[10],"leechAction":1,"leechFails":8,"minInt":1,"mult":0},"dyn":false}}
        """

        try exec(db, """
        INSERT INTO col VALUES(
            1, \(nowMs), \(nowMs), \(nowMs), 11, 0, 0, 0,
            '\(escapeSQL(conf))',
            '\(escapeSQL(models))',
            '\(escapeSQL(decks))',
            '\(escapeSQL(dconf))',
            '{}'
        );
        """)

        var noteID: Int64 = 1_000_000_001
        var cardDue = 1

        for card in cards {
            let front = ankiFront(for: card)
            let back = ankiBack(for: card)
            let flds = "\(escapeField(front))\u{1f}\(escapeField(back))"
            let guid = ankiGUID(from: card.id)
            let tags = sanitizedTag(card.word)
            let csum = fieldChecksum(front)
            let sfld = sortFieldHash(front)

            try exec(db, """
            INSERT INTO notes VALUES(
                \(noteID), '\(guid)', \(modelID), \(nowMs), 0, '\(escapeSQL(tags))',
                '\(escapeSQL(flds))', \(sfld), \(csum), 0, ''
            );
            """)

            try exec(db, """
            INSERT INTO cards VALUES(
                \(noteID), \(noteID), \(deckID), 0, \(nowMs), 0,
                0, 0, \(cardDue), 0, 2500, 0, 0, 0, 0, 0, 0, ''
            );
            """)

            noteID += 1
            cardDue += 1
        }
    }

    private static func ankiFront(for card: FlashCard) -> String {
        var lines: [String] = []
        if let phonetic = card.phonetic, !phonetic.isEmpty {
            lines.append("\(card.word) \(phonetic)")
        } else {
            lines.append(card.word)
        }
        lines.append(card.front)
        return lines.joined(separator: "\n")
    }

    private static func ankiBack(for card: FlashCard) -> String {
        var parts = [card.displayBack]
        if !card.sentence.isEmpty {
            parts.append("— \(card.sentence)")
        }
        return parts.joined(separator: "\n\n")
    }

    private static func ankiGUID(from id: UUID) -> String {
        String(id.uuidString.replacingOccurrences(of: "-", with: "").prefix(10))
    }

    private static func sanitizedTag(_ word: String) -> String {
        word
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
    }

    private static func escapeField(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{1f}", with: " ")
    }

    private static func escapeSQL(_ text: String) -> String {
        text.replacingOccurrences(of: "'", with: "''")
    }

    private static func fieldChecksum(_ text: String) -> Int {
        let data = Data(text.utf8)
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1 != 0) ? ((crc >> 1) ^ 0xEDB8_8320) : (crc >> 1)
            }
        }
        return Int((crc ^ 0xFFFF_FFFF) & 0xFFFF)
    }

    private static func sortFieldHash(_ text: String) -> Int {
        let lowered = text.lowercased()
        var hash: UInt64 = 0
        for byte in lowered.utf8 {
            hash = hash &* 31 &+ UInt64(byte)
        }
        return Int(hash & 0x7FFF_FFFF)
    }

    private static func basicModelJSON() -> String {
        """
        {"\(modelID)":{"id":\(modelID),"name":"Basic","type":0,"mod":0,"usn":0,"sortf":0,"did":\(deckID),"tmpls":[{"name":"Card 1","ord":0,"qfmt":"{{Front}}","afmt":"{{FrontSide}}\\n\\n<hr id=answer>\\n\\n{{Back}}","bqfmt":"","bafmt":"","did":null,"bfont":"","bsize":0}],"flds":[{"name":"Front","ord":0,"sticky":false,"rtl":false,"font":"Arial","size":20,"media":[]},{"name":"Back","ord":1,"sticky":false,"rtl":false,"font":"Arial","size":20,"media":[]}],"css":".card{font-family:arial;font-size:20px;text-align:center;color:black;background-color:white;}","latexPre":"\\\\documentclass[12pt]{article}\\n\\\\usepackage[utf8]{inputenc}\\n\\\\usepackage{amssymb,amsmath}\\n\\\\pagestyle{empty}\\n\\\\begin{document}\\n","latexPost":"\\\\end{document}","latexsvg":false}}
        """
    }

    private static func exec(_ db: OpaquePointer, _ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "unknown sqlite error"
            sqlite3_free(errorMessage)
            throw ApkgExportError.sqliteError(message)
        }
    }
}

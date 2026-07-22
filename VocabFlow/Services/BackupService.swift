import Foundation
import SwiftData

enum BackupService {
    static let defaultFilename = "vocabflow-backup"

    static func export(cards: [FlashCard]) throws -> Data {
        let backup = FlashCardBackupFile(
            version: 1,
            exportedAt: Date(),
            cards: cards.map(FlashCardBackup.init(from:))
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }

    static func importMerge(data: Data, into context: ModelContext) throws -> (added: Int, updated: Int) {
        let backup = try decode(data)
        var added = 0
        var updated = 0

        for item in backup.cards {
            if let existing = try fetchCard(id: item.id, in: context) {
                item.apply(to: existing)
                updated += 1
            } else {
                context.insert(item.makeFlashCard())
                added += 1
            }
        }

        try context.save()
        return (added, updated)
    }

    static func importReplace(data: Data, into context: ModelContext) throws -> Int {
        let existing = try context.fetch(FetchDescriptor<FlashCard>())
        existing.forEach { context.delete($0) }

        let backup = try decode(data)
        backup.cards.forEach { context.insert($0.makeFlashCard()) }

        try context.save()
        return backup.cards.count
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

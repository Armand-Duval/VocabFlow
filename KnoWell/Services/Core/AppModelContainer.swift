import Foundation
import SwiftData

enum AppModelContainer {
    static let shared: ModelContainer = {
        if let container = makeContainer(recoverIfNeeded: false) {
            return container
        }
        if let container = makeContainer(recoverIfNeeded: true) {
            return container
        }
        fatalError("Unable to create SwiftData ModelContainer")
    }()

    private static func makeContainer(recoverIfNeeded: Bool) -> ModelContainer? {
        let schema = Schema([FlashCard.self, Deck.self])
        let groupID = ShareImportStore.appGroupID

        if recoverIfNeeded {
            removePersistentStore(in: groupID)
        }

        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            groupContainer: .identifier(groupID)
        )

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            NSLog("AppModelContainer failed (recoverIfNeeded=\(recoverIfNeeded)): \(error.localizedDescription)")
            return nil
        }
    }

    private static func removePersistentStore(in groupID: String) {
        guard let supportURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent("Library/Application Support") else {
            return
        }

        let base = supportURL.appendingPathComponent("default.store").path
        let fileManager = FileManager.default
        for suffix in ["", "-shm", "-wal"] {
            try? fileManager.removeItem(atPath: base + suffix)
        }
    }
}

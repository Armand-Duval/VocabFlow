import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum ShareCardGenerationRunner {
    /// Persist a pending job for the main app queue, then exit the extension immediately.
    static func prepareShareJob(
        sentence: String,
        words: [String],
        sourceHint: String? = nil,
        sourceImagePath: String? = nil,
        targetDeckID: UUID
    ) throws -> (keptWords: [String], skippedCount: Int) {
        SharedDeckStore.lastSelectedDeckID = targetDeckID
        SharedDeckStore.pendingTargetDeckID = targetDeckID

        let prepared = try CardGenerator.prepareGeneration(
            sentence: sentence,
            words: words,
            skipExistingInDeckID: targetDeckID
        )
        let keptWords = prepared.units.flatMap(\.words)
        ShareImportStore.savePendingGenerationJob(
            sentence: sentence,
            words: keptWords,
            sourceHint: sourceHint,
            sourceImagePath: sourceImagePath,
            deckID: targetDeckID
        )
        ShareImportStore.clear()
        #if canImport(UIKit)
        UIPasteboard.general.string = sentence
        #endif
        return (keptWords, prepared.skippedCount)
    }

    static func submitFromShareExtension(
        sentence: String,
        words: [String],
        sourceHint: String? = nil,
        sourceImagePath: String? = nil,
        targetDeckID: UUID,
        exitExtension: @escaping () -> Void
    ) {
        do {
            _ = try prepareShareJob(
                sentence: sentence,
                words: words,
                sourceHint: sourceHint,
                sourceImagePath: sourceImagePath,
                targetDeckID: targetDeckID
            )
        } catch {
            ShareExtensionNotifier.scheduleNoticeNotification(
                body: error.localizedDescription
            )
            exitExtension()
            return
        }

        ShareExtensionNotifier.scheduleNoticeNotification(body: L10n.createQueuedToast)
        AppLog.info("submitFromShareExtension deck=\(targetDeckID) words=\(words.count)", category: "Share")
        exitExtension()
    }
}

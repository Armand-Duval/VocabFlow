import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum ShareCardGenerationRunner {
    static func submitFromShareExtension(
        sentence: String,
        words: [String],
        sourceHint: String? = nil,
        targetDeckID: UUID,
        exitExtension: @escaping () -> Void
    ) {
        SharedDeckStore.lastSelectedDeckID = targetDeckID
        SharedDeckStore.pendingTargetDeckID = targetDeckID

        // Early exit before queuing work / “generating” notification.
        let filtered = SharedDedupeIndex.filterNewWords(
            words,
            deckID: targetDeckID,
            sentence: sentence
        )
        guard !filtered.kept.isEmpty else {
            ShareExtensionNotifier.scheduleNoticeNotification(
                body: L10n.createGenerateAllDuplicates
            )
            exitExtension()
            return
        }

        ShareImportStore.savePendingGenerationJob(
            sentence: sentence,
            words: filtered.kept,
            sourceHint: sourceHint
        )
        UIPasteboard.general.string = sentence
        ShareExtensionNotifier.scheduleGeneratingNotification()

        exitExtension()

        Task {
            await processPendingJobIfNeeded(resetStale: false)
        }
    }

    static func processPendingJobIfNeeded(resetStale: Bool = false) async {
        if resetStale {
            ShareImportStore.resetStaleProcessingJob()
        }
        guard let job = ShareImportStore.claimPendingGenerationJob() else { return }

        let deckID = SharedDeckStore.pendingTargetDeckID
            ?? SharedDeckStore.lastSelectedDeckID

        do {
            let deckName = SharedDeckStore.loadCatalog()
                .first(where: { $0.id == SharedDeckStore.lastSelectedDeckID })?
                .name
            let drafts = try await KimiCardGenerator.generate(
                sentence: job.sentence,
                words: job.words,
                sourceHint: job.sourceHint,
                deckName: deckName,
                skipExistingInDeckID: deckID
            )

            guard !drafts.isEmpty else {
                ShareImportStore.clearGenerationJob()
                ShareExtensionNotifier.scheduleFailureNotification(
                    message: L10n.generateEmptyError
                )
                return
            }

            ShareImportStore.saveGeneratedDrafts(drafts)
            ShareImportStore.clearGenerationJob()
            ShareExtensionNotifier.scheduleImportReadyNotification(cardCount: drafts.count)
        } catch let error as KimiCardGeneratorError {
            ShareImportStore.clearGenerationJob()
            if case .allDuplicates = error {
                ShareExtensionNotifier.scheduleNoticeNotification(
                    body: L10n.createGenerateAllDuplicates
                )
            } else {
                ShareExtensionNotifier.scheduleFailureNotification(
                    message: error.localizedDescription
                )
            }
        } catch {
            ShareImportStore.clearGenerationJob()
            ShareExtensionNotifier.scheduleFailureNotification(message: error.localizedDescription)
        }
    }
}

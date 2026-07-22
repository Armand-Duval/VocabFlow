import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum ShareCardGenerationRunner {
    static func submitFromShareExtension(
        sentence: String,
        words: [String],
        targetDeckID: UUID,
        exitExtension: @escaping () -> Void
    ) {
        SharedDeckStore.lastSelectedDeckID = targetDeckID
        SharedDeckStore.pendingTargetDeckID = targetDeckID
        ShareImportStore.savePendingGenerationJob(sentence: sentence, words: words)
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

        do {
            let drafts = try await KimiCardGenerator.generate(
                sentence: job.sentence,
                words: job.words
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
        } catch {
            ShareImportStore.clearGenerationJob()
            ShareExtensionNotifier.scheduleFailureNotification(message: error.localizedDescription)
        }
    }
}

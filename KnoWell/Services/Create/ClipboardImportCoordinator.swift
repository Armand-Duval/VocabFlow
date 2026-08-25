import UIKit

@MainActor
final class ClipboardImportCoordinator {
    private var lastChangeCount = UIPasteboard.general.changeCount
    private var lastImportedChangeCount: Int?
    private var hasInitializedPasteboard = false

    func checkClipboardIfNeeded(shareImport: ShareImportCoordinator) {
        guard !shareImport.hasPendingImport else { return }

        let pasteboard = UIPasteboard.general

        if !hasInitializedPasteboard {
            lastChangeCount = pasteboard.changeCount
            hasInitializedPasteboard = true
            return
        }

        guard pasteboard.changeCount != lastChangeCount else { return }

        let newChangeCount = pasteboard.changeCount
        lastChangeCount = newChangeCount

        guard newChangeCount != lastImportedChangeCount else { return }

        guard let text = pasteboard.string?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            text.count >= 2 else {
            return
        }

        let parsed = Preprocess.parsePaste(text)
        shareImport.importPayload(
            ShareImportPayload(
                sentence: parsed.sentence,
                selectedWord: parsed.prefilledWords.isEmpty
                    ? nil
                    : VocabularyWords.join(parsed.prefilledWords),
                source: .clipboard
            )
        )
        lastImportedChangeCount = newChangeCount
    }
}

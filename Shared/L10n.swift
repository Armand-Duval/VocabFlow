import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum L10n {
    // MARK: - Tabs

    static var tabCreate: String { tr("tab.create") }
    static var tabReview: String { tr("tab.review") }
    static var tabLibrary: String { tr("tab.library") }
    static var tabSettings: String { tr("tab.settings") }

    // MARK: - Common

    static var ok: String { tr("common.ok") }
    static var cancel: String { tr("common.cancel") }
    static var close: String { tr("common.close") }
    static var done: String { tr("common.done") }
    static var add: String { tr("common.add") }

    // MARK: - Create cards

    static var createTitle: String { tr("create.title") }
    static var sourceText: String { tr("create.source") }
    static var sourcePlaceholder: String { tr("create.source.placeholder") }
    static var wordsSection: String { tr("create.words") }
    static var generateCards: String { tr("create.generate") }
    static var generating: String { tr("create.generating") }
    static var usingDefaultKey: String { tr("create.defaultKey") }
    static var createTipTitle: String { tr("create.tip.title") }
    static var createTipBody: String { tr("create.tip.body") }
    static var createTipDismiss: String { tr("create.tip.dismiss") }
    static var sourceFooter: String { tr("create.source.footer") }
    static var wordsFooter: String { tr("create.words.footer") }
    static var addSelection: String { tr("create.addSelection") }
    static func addSelectionWord(_ word: String) -> String {
        tf("create.addSelection.word", word)
    }

    static var importClipboardSentence: String { tr("import.clipboard.sentence") }
    static var importClipboardWord: String { tr("import.clipboard.word") }
    static var importClipboardBoth: String { tr("import.clipboard.both") }
    static var importShareSentence: String { tr("import.share.sentence") }
    static var importShareBoth: String { tr("import.share.both") }

    static var generateFailedTitle: String { tr("create.error.title") }
    static var generateEmptyError: String { tr("create.error.empty") }

    // MARK: - Words editor

    static var wordsEmptyHint: String { tr("words.emptyHint") }
    static var wordsManualPlaceholder: String { tr("words.manualPlaceholder") }
    static var selectionEmpty: String { tr("words.selectionEmpty") }
    static func wordAdded(_ word: String) -> String { tf("words.added", word) }
    static func wordDuplicate(_ word: String) -> String { tf("words.duplicate", word) }
    static var addToVocabulary: String { tr("words.addToVocabulary") }

    // MARK: - Extension form

    static var extensionHint: String { tr("extension.hint") }
    static var extensionWordsFooter: String { tr("extension.wordsFooter") }
    static var extensionSubmitFailedTitle: String { tr("extension.error.title") }
    static var extensionMissingKey: String { tr("extension.error.missingKey") }
    static var extensionNoContent: String { tr("extension.error.noContent") }
    static var extensionNoText: String { tr("extension.error.noText") }

    // MARK: - Preview

    static var previewTitle: String { tr("preview.title") }
    static var previewIntro: String { tr("preview.intro") }
    static var includeInLibrary: String { tr("preview.include") }
    static var wordLabel: String { tr("preview.word") }
    static var typeLabel: String { tr("preview.type") }
    static var frontLabel: String { tr("preview.front") }
    static var backLabel: String { tr("preview.back") }
    static var backPlaceholder: String { tr("preview.back.placeholder") }
    static func saveCount(_ count: Int) -> String { tf("preview.save", count) }
    static var savedTitle: String { tr("preview.saved.title") }
    static var savedMessage: String { tr("preview.saved.message") }
    static var phoneticLabel: String { tr("preview.phonetic") }
    static var phoneticPlaceholder: String { tr("preview.phonetic.placeholder") }
    static var speakWord: String { tr("speech.word") }
    static var speakSentence: String { tr("speech.sentence") }
    static var importFromPhoto: String { tr("import.photo") }
    static var importFromPhotoSuccess: String { tr("import.photo.success") }
    static var recognizingPhoto: String { tr("import.photo.recognizing") }
    static var ocrEmpty: String { tr("import.ocr.empty") }
    static var ocrFailed: String { tr("import.ocr.failed") }

    // MARK: - Card types

    static var cardTypeCloze: String { tr("cardType.cloze") }
    static var cardTypeDefinition: String { tr("cardType.definition") }

    // MARK: - Review

    static var reviewTitle: String { tr("review.title") }
    static var reviewEmptyTitle: String { tr("review.empty.title") }
    static var reviewEmptyNoCards: String { tr("review.empty.noCards") }
    static var reviewEmptyDone: String { tr("review.empty.done") }
    static var noCardsToReview: String { tr("review.noCards") }
    static var cardFront: String { tr("review.card.front") }
    static var cardBack: String { tr("review.card.back") }
    static var tapToReveal: String { tr("review.tapReveal") }
    static var tapToFlipBack: String { tr("review.tapFlip") }
    static var showAnswer: String { tr("review.showAnswer") }
    static var studyTitle: String { tr("review.study") }

    static var ratingAgain: String { tr("rating.again") }
    static var ratingHard: String { tr("rating.hard") }
    static var ratingGood: String { tr("rating.good") }
    static var ratingEasy: String { tr("rating.easy") }
    static func intervalMinutes(_ count: Int) -> String { tf("interval.minutes", count) }
    static func intervalHours(_ count: Int) -> String { tf("interval.hours", count) }
    static func intervalDays(_ count: Int) -> String { tf("interval.days", count) }
    static func reviewProgress(_ current: Int, _ total: Int) -> String {
        tf("review.progress", current, total)
    }
    static var reviewLearningWaitTitle: String { tr("review.learning.wait.title") }
    static func reviewLearningWaitMessage(_ interval: String) -> String {
        tf("review.learning.wait.message", interval)
    }

    // MARK: - Library

    static var libraryTitle: String { tr("library.title") }
    static var libraryEmptyTitle: String { tr("library.empty.title") }
    static var libraryEmptyMessage: String { tr("library.empty.message") }
    static var libraryNoResultsTitle: String { tr("library.noResults.title") }
    static var libraryNoResultsMessage: String { tr("library.noResults.message") }
    static var librarySearchPrompt: String { tr("library.search") }
    static var dueForReview: String { tr("library.due") }
    static func reviewAll(_ word: String, count: Int) -> String {
        tf("library.reviewAll", word, count)
    }
    static func nextReview(_ date: String) -> String {
        tf("library.nextReview", date)
    }

    // MARK: - Review quota

    static var reviewQuotaNew: String { tr("review.quota.newLabel") }
    static var reviewQuotaReview: String { tr("review.quota.reviewLabel") }
    static func reviewQuotaProgress(_ title: String, studied: Int, limit: Int) -> String {
        tf("review.quota.progress", title, studied, limitDisplay(limit))
    }
    static var reviewQuotaReachedTitle: String { tr("review.quota.reached.title") }
    static func reviewQuotaReachedMessage(_ count: Int) -> String {
        tf("review.quota.reached.message", count)
    }
    private static func limitDisplay(_ limit: Int) -> String {
        limit == 0 ? tr("review.quota.unlimited") : "\(limit)"
    }

    static var settingsReviewSection: String { tr("settings.review.section") }
    static func settingsReviewNewLimit(_ limit: Int) -> String {
        tf("settings.review.newLimit", limitDisplay(limit))
    }
    static func settingsReviewReviewLimit(_ limit: Int) -> String {
        tf("settings.review.reviewLimit", limitDisplay(limit))
    }
    static var settingsReviewFooter: String { tr("settings.review.footer") }
    static var settingsReviewReminderEnabled: String { tr("settings.review.reminder.enabled") }
    static var settingsReviewReminderTime: String { tr("settings.review.reminder.time") }
    static func reviewReminderBody(_ count: Int) -> String { tf("review.reminder.body", count) }

    // MARK: - Settings

    static var settingsTitle: String { tr("settings.title") }
    static var settingsSavedTitle: String { tr("settings.saved.title") }
    static var apiKeySection: String { tr("settings.apiKey") }
    static var apiKeyPlaceholder: String { tr("settings.apiKey.placeholder") }
    static var apiKeyFooter: String { tr("settings.apiKey.footer") }
    static var modelSection: String { tr("settings.model") }
    static var saveSettings: String { tr("settings.save") }
    static var statusSection: String { tr("settings.status") }
    static var statusReady: String { tr("settings.status.ready") }
    static var statusMissingKey: String { tr("settings.status.missing") }
    static var keySourceUser: String { tr("settings.key.user") }
    static var keySourceDefault: String { tr("settings.key.default") }
    static var keySourceMissing: String { tr("settings.key.missing") }

    static var importShareSection: String { tr("settings.import.share.section") }
    static var importShareStep1: String { tr("settings.import.share.step1") }
    static var importShareStep2: String { tr("settings.import.share.step2") }
    static var importCopySection: String { tr("settings.import.copy.section") }
    static var importCopyStep1: String { tr("settings.import.copy.step1") }
    static var importCopyStep2: String { tr("settings.import.copy.step2") }
    static var importCopyStep3: String { tr("settings.import.copy.step3") }
    static var importCopyFooter: String { tr("settings.import.copy.footer") }
    static var importHelpTitle: String { tr("settings.import.help") }

    static var backupSection: String { tr("settings.backup.section") }
    static var exportBackup: String { tr("settings.backup.export") }
    static var importBackup: String { tr("settings.backup.import") }
    static func backupFooter(_ count: Int) -> String { tf("settings.backup.footer", count) }

    static var importModeTitle: String { tr("settings.importMode.title") }
    static var importModeMerge: String { tr("settings.importMode.merge") }
    static var importModeReplace: String { tr("settings.importMode.replace") }
    static var importModeMessage: String { tr("settings.importMode.message") }
    static var exportFailed: String { tr("settings.export.failed") }
    static var readFailed: String { tr("settings.read.failed") }
    static var importFailed: String { tr("settings.import.failed") }
    static var importComplete: String { tr("settings.import.complete") }
    static func importMergeResult(added: Int, updated: Int) -> String {
        tf("settings.import.mergeResult", added, updated)
    }
    static func importReplaceResult(_ count: Int) -> String {
        tf("settings.import.replaceResult", count)
    }

    // MARK: - Notifications

    static var notificationGenerating: String { tr("notification.generating") }
    static func notificationReady(_ count: Int) -> String { tf("notification.ready", count) }
    static var notificationReadyGeneric: String { tr("notification.ready.generic") }
    static func notificationSaved(_ count: Int) -> String { tf("notification.saved", count) }
    static func notificationFailed(_ message: String) -> String { tf("notification.failed", message) }

    // MARK: - Errors

    static var missingAPIKeyError: String { tr("error.missingAPIKey") }
    static func parseError(_ message: String) -> String { tf("error.parse", message) }

    // MARK: - Helpers

    private static func tr(_ key: String.LocalizationValue) -> String {
        String(localized: key)
    }

    private static func tf(_ key: String.LocalizationValue, _ arguments: CVarArg...) -> String {
        String(format: String(localized: key), locale: Locale.current, arguments: arguments)
    }
}

enum VocabularyWordFeedback {
    static func apply(
        _ result: VocabularyWordAddResult,
        message: inout String?,
        isError: inout Bool
    ) {
        switch result {
        case .added:
            message = nil
            isError = false
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        case let .duplicate(word):
            message = L10n.wordDuplicate(word)
            isError = true
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
        case .empty:
            message = L10n.selectionEmpty
            isError = true
        }
    }
}

import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(Security)
import Security
#endif

enum L10n {
    // MARK: - Tabs

    static var tabCreate: String { tr("tab.create") }
    static var tabReview: String { tr("tab.review") }
    static var tabLibrary: String { tr("tab.library") }
    static var tabSettings: String { tr("tab.settings") }
    static var brandNameZH: String { tr("brand.name.zh") }
    static var brandNameEN: String { tr("brand.name.en") }
    static var homeStatDue: String { tr("home.stat.due") }
    static var homeStatNewQuota: String { tr("home.stat.newQuota") }
    static var homeStatStreak: String { tr("home.stat.streak") }
    static func homeStatStreakValue(_ days: Int) -> String { tf("home.stat.streakValue", days) }
    static var homeRecentDecks: String { tr("home.recentDecks") }
    static var createAIGenerate: String { tr("create.aiGenerate") }
    static var createPastePlaceholder: String { tr("create.pastePlaceholder") }
    static var createLiteraryLead: String { tr("create.literaryLead") }
    static var createAddWord: String { tr("create.addWord") }
    static var createManageDeck: String { tr("create.manageDeck") }

    // MARK: - Common

    static var ok: String { tr("common.ok") }
    static var cancel: String { tr("common.cancel") }
    static var close: String { tr("common.close") }
    static var done: String { tr("common.done") }
    static var back: String { tr("common.back") }
    static var clear: String { tr("common.clear") }
    static var add: String { tr("common.add") }

    // MARK: - Create cards

    static var createTitle: String { tr("create.title") }
    static var createQuickCaptureTitle: String { tr("create.quickCapture.title") }
    static var createQuickPaste: String { tr("create.quickCapture.paste") }
    static var sourceText: String { tr("create.source") }
    static var sourcePlaceholder: String { tr("create.source.placeholder") }
    static var wordsSection: String { tr("create.words") }
    static var generateCards: String { tr("create.generate") }
    static var generateCardsShort: String { tr("create.generate.short") }
    static var createQuickPhoto: String { tr("create.quick.photo") }
    static var createQuickCamera: String { tr("create.quick.camera") }
    static var createQuickPending: String { tr("create.quick.pending") }
    static var createPendingImportTitle: String { tr("create.pending.importTitle") }
    static func createPendingDraftsSubtitle(_ count: Int) -> String { tf("create.pending.draftsSubtitle", count) }
    static var createPendingAction: String { tr("create.pending.action") }
    static var createGenerateHint: String { tr("create.generate.hint") }
    static func createGenerateSuccess(_ count: Int) -> String { tf("create.generate.success", count) }
    static func createCharCount(_ count: Int) -> String { tf("create.source.charCount", count) }
    static var createSourceEmptyHint: String { tr("create.source.emptyHint") }
    static var createSourceFooterHint: String { tr("create.source.footerHint") }
    static var createSourceLongHint: String { tr("create.source.longHint") }
    static var createWordsEmptyHint: String { tr("create.words.emptyHint") }
    static var createLongTextTitle: String { tr("create.longText.title") }
    static var createLongTextMessage: String { tr("create.longText.message") }
    static var createLongTextKeepSentence: String { tr("create.longText.keepSentence") }
    static var createLongTextSplitWords: String { tr("create.longText.splitWords") }
    static var createLongTextSplitFallback: String { tr("create.longText.splitFallback") }
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
    static var cardSentenceTranslation: String { tr("card.sentenceTranslation") }
    static var cardTranslationHighlight: String { tr("card.translationHighlight") }
    static var cardTranslationHighlightFooter: String { tr("card.translationHighlight.footer") }
    static var cardTranslationHighlightMissing: String { tr("card.translationHighlight.missing") }
    static var cardTranslationHighlightPreview: String { tr("card.translationHighlight.preview") }
    static var cardSourceLabel: String { tr("card.source") }
    static func cardSource(_ value: String) -> String { tf("card.source.value", value) }
    static func saveCount(_ count: Int) -> String { tf("preview.save", count) }
    static var savedTitle: String { tr("preview.saved.title") }
    static var savedMessage: String { tr("preview.saved.message") }
    static var phoneticLabel: String { tr("preview.phonetic") }
    static var phoneticPlaceholder: String { tr("preview.phonetic.placeholder") }
    static var speakWord: String { tr("speech.word") }
    static var speakSentence: String { tr("speech.sentence") }
    static var importFromPhoto: String { tr("import.photo") }
    static var importFromPhotoSuccess: String { tr("import.photo.success") }
    static var importFromCamera: String { tr("import.camera") }
    static var importFromCameraSuccess: String { tr("import.camera.success") }
    static var recognizingPhoto: String { tr("import.photo.recognizing") }
    static var ocrEmpty: String { tr("import.ocr.empty") }
    static var ocrFailed: String { tr("import.ocr.failed") }
    static func ocrHighlightDetected(_ count: Int) -> String {
        tf("import.ocr.highlightDetected", count)
    }
    static func ocrHighlightContext(_ wordCount: Int, _ sentenceCount: Int) -> String {
        tf("import.ocr.highlightContext", wordCount, sentenceCount)
    }

    // MARK: - Card types

    static var cardTypeCloze: String { tr("cardType.cloze") }
    static var cardTypeDefinition: String { tr("cardType.definition") }

    // MARK: - Review

    static var reviewTitle: String { tr("review.title") }
    static var reviewEmptyTitle: String { tr("review.empty.title") }
    static var reviewEmptyNoCards: String { tr("review.empty.noCards") }
    static var reviewEmptyGoCreate: String { tr("review.empty.goCreate") }
    static var reviewEmptyAssistant: String { tr("review.empty.assistant") }
    static var reviewEmptyStartCreate: String { tr("review.empty.startCreate") }
    static var reviewEmptyDone: String { tr("review.empty.done") }
    static var noCardsToReview: String { tr("review.noCards") }
    static var cardFront: String { tr("review.card.front") }
    static var cardBack: String { tr("review.card.back") }
    static var tapToReveal: String { tr("review.tapReveal") }
    static var tapToFlipBack: String { tr("review.tapFlip") }
    static var showAnswer: String { tr("review.showAnswer") }
    static var studyTitle: String { tr("review.study") }
    static func reviewHomeDueCount(_ count: Int) -> String { tf("review.home.dueCount", count) }
    static var reviewHomeStart: String { tr("review.home.start") }
    static func reviewHomeContinueDeck(_ name: String) -> String { tf("review.home.continueDeck", name) }
    static var reviewHomeQuotaLink: String { tr("review.home.quotaLink") }
    static var reviewHomeQuickCapture: String { tr("review.home.quickCapture") }
    static var reviewHomeRecentDecks: String { tr("review.home.recentDecks") }
    static var reviewHomeBack: String { tr("review.home.back") }
    static var reviewHomeDoneToday: String { tr("review.home.doneToday") }
    static var reviewHomeDoneHint: String { tr("review.home.doneHint") }
    static var reviewHomeDoneOffer: String { tr("review.home.doneOffer") }
    static var reviewDailyTitle: String { tr("review.daily.title") }
    static var reviewDailyFromLibrary: String { tr("review.daily.fromLibrary") }
    static var reviewDailyCollect: String { tr("review.daily.collect") }
    static var reviewSessionDone: String { tr("review.session.done") }

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

    static var libraryEdit: String { tr("library.edit") }
    static func libraryEditTitle(_ word: String) -> String { tf("library.edit.title", word) }
    static var libraryEditBasics: String { tr("library.edit.basics") }
    static var libraryEditFrontSection: String { tr("library.edit.frontSection") }
    static var libraryEditBackSection: String { tr("library.edit.backSection") }
    static var libraryEditFrontFooter: String { tr("library.edit.frontFooter") }
    static var libraryEditBackFooter: String { tr("library.edit.backFooter") }
    static var cardRegenerate: String { tr("card.regenerate") }
    static var cardRegenerateMessage: String { tr("card.regenerate.message") }
    static var cardRegenerateEditMessage: String { tr("card.regenerate.editMessage") }
    static var cardRegenerateRunning: String { tr("card.regenerate.running") }
    static var cardRegenerateDone: String { tr("card.regenerate.done") }
    static var cardRegenerateNoMatch: String { tr("card.regenerate.noMatch") }
    static var libraryResetSRS: String { tr("library.resetSRS") }
    static var libraryResetSRSMessage: String { tr("library.resetSRS.message") }
    static var libraryDeleteCard: String { tr("library.deleteCard") }
    static var libraryDeleteCardMessage: String { tr("library.deleteCard.message") }
    static var libraryReviewThisCard: String { tr("library.reviewThisCard") }
    static var libraryDetailContent: String { tr("library.detail.content") }
    static var libraryDetailSRS: String { tr("library.detail.srs") }
    static var librarySRSStatus: String { tr("library.srs.status") }
    static var librarySRSNextReview: String { tr("library.srs.nextReview") }
    static var librarySRSReviewCount: String { tr("library.srs.reviewCount") }
    static var librarySRSInterval: String { tr("library.srs.interval") }
    static var librarySRSEase: String { tr("library.srs.ease") }
    static var librarySRSNew: String { tr("library.srs.new") }
    static var librarySRSScheduled: String { tr("library.srs.scheduled") }
    static var libraryContextNote: String { tr("library.contextNote") }
    static var cardSuspend: String { tr("card.suspend") }
    static var cardUnsuspend: String { tr("card.unsuspend") }
    static var cardSuspendedStatus: String { tr("card.suspended.status") }
    static var cardSuspendedHint: String { tr("card.suspended.hint") }
    static var cardSuspendedDone: String { tr("card.suspended.done") }
    static var cardUnsuspendedDone: String { tr("card.unsuspended.done") }
    static var cardExportApkg: String { tr("card.export.apkg") }
    static var deckExportApkg: String { tr("deck.export.apkg") }

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
    static var reviewQuotaDetailTitle: String { tr("review.quota.detail.title") }
    static var reviewQuotaDetailToday: String { tr("review.quota.detail.today") }
    static func reviewQuotaDetailDeferred(_ count: Int) -> String {
        tf("review.quota.detail.deferred", count)
    }
    static func reviewQuotaDetailDeferredMessage(_ count: Int) -> String {
        tf("review.quota.detail.deferredMessage", count)
    }
    static var reviewQuotaDetailHint: String { tr("review.quota.detail.hint") }
    static var reviewRatingHint: String { tr("review.rating.hint") }
    static var reviewSwipeHint: String { tr("review.swipe.hint") }
    static var reviewDeckFilterAll: String { tr("review.deckFilter.all") }
    private static func limitDisplay(_ limit: Int) -> String {
        limit == 0 ? tr("review.quota.unlimited") : "\(limit)"
    }

    static var settingsReviewSection: String { tr("settings.review.section") }
    static var settingsReviewUnlimited: String { tr("settings.review.unlimited") }
    static var settingsReviewNewLimitLabel: String { tr("settings.review.newLimit") }
    static var settingsReviewReviewLimitLabel: String { tr("settings.review.reviewLimit") }
    static var settingsReviewFooter: String { tr("settings.review.footer") }
    static var settingsReviewReminderEnabled: String { tr("settings.review.reminder.enabled") }
    static var settingsReviewReminderTime: String { tr("settings.review.reminder.time") }
    static func reviewReminderBody(_ count: Int) -> String { tf("review.reminder.body", count) }

    // MARK: - Settings

    static var settingsTitle: String { tr("settings.title") }
    static var settingsSavedTitle: String { tr("settings.saved.title") }
    static var settingsAISection: String { tr("settings.ai.section") }
    static var settingsImportSection: String { tr("settings.import.section") }
    static var settingsImportExportSection: String { tr("settings.importExport.section") }
    static var settingsOpenDeckStore: String { tr("settings.openDeckStore") }
    static var settingsImportFormatsFooter: String { tr("settings.import.formatsFooter") }
    static var settingsAIKeyFooter: String { tr("settings.ai.keyFooter") }
    static var settingsTestAPI: String { tr("settings.testAPI") }
    static var settingsTestingAPI: String { tr("settings.testAPI.testing") }
    static var settingsTestAPITitle: String { tr("settings.testAPI.title") }
    static var settingsTestAPISuccess: String { tr("settings.testAPI.success") }
    static func settingsTestAPIFailed(_ message: String) -> String { tf("settings.testAPI.failed", message) }
    static var settingsHelpTitle: String { tr("settings.help.title") }
    static var settingsHelpBYOK: String { tr("settings.help.byok") }
    static var settingsHelpApkg: String { tr("settings.help.apkg") }
    static var settingsHelpShare: String { tr("settings.help.share") }
    static var settingsModel8kDetail: String { tr("settings.model.8k.detail") }
    static var settingsModel32kDetail: String { tr("settings.model.32k.detail") }
    static var settingsModelK2Detail: String { tr("settings.model.k2.detail") }
    static var settingsModelK26Detail: String { tr("settings.model.k26.detail") }
    static var settingsModelDefaultDetail: String { tr("settings.model.default.detail") }
    static var libraryQuickImport: String { tr("library.quick.import") }
    static var libraryQuickExport: String { tr("library.quick.export") }
    static var deckImporting: String { tr("deck.importing") }
    static var exportBackupSuccess: String { tr("settings.exportBackup.success") }
    static var settingsDataSection: String { tr("settings.data.section") }
    static var settingsMaintenanceSection: String { tr("settings.maintenance.section") }
    static var settingsMaintenanceFooter: String { tr("settings.maintenance.footer") }
    static var settingsAboutSection: String { tr("settings.about.section") }
    static func settingsDataFooter(_ count: Int) -> String { tf("settings.data.footer", count) }
    static var exportApkg: String { tr("settings.apkg.export") }
    static var settingsResetAllSRS: String { tr("settings.resetAllSRS") }
    static var settingsResetAllSRSMessage: String { tr("settings.resetAllSRS.message") }
    static var settingsResetAllSRSDone: String { tr("settings.resetAllSRS.done") }
    static var settingsResetAllSRSDoneMessage: String { tr("settings.resetAllSRS.doneMessage") }
    static var settingsMigrateCards: String { tr("settings.migrateCards") }
    static var settingsMigrateCardsMessage: String { tr("settings.migrateCards.message") }
    static var settingsMigrateCardsRunning: String { tr("settings.migrateCards.running") }
    static var settingsMigrateCardsDone: String { tr("settings.migrateCards.done") }
    static func settingsMigrateCardsDoneMessage(
        _ fronts: Int,
        _ backs: Int,
        _ phonetics: Int,
        _ sources: Int,
        _ ai: Int,
        _ failures: Int
    ) -> String {
        tf("settings.migrateCards.doneMessage", fronts, backs, phonetics, sources, ai, failures)
    }
    static var settingsDeleteAllCards: String { tr("settings.deleteAllCards") }
    static var settingsDeleteAllCardsMessage: String { tr("settings.deleteAllCards.message") }
    static var settingsDeleteAllDone: String { tr("settings.deleteAllCards.done") }
    static var settingsDeleteAllDoneMessage: String { tr("settings.deleteAllCards.doneMessage") }
    static var apiKeySection: String { tr("settings.apiKey") }
    static var apiKeyPlaceholder: String { tr("settings.apiKey.placeholder") }
    static var apiKeyFooter: String { tr("settings.apiKey.footer") }
    static var modelSection: String { tr("settings.model") }
    static var aiProviderSection: String { tr("settings.ai.provider") }
    static var aiProviderMoonshot: String { tr("settings.ai.provider.moonshot") }
    static var aiProviderOpenAI: String { tr("settings.ai.provider.openai") }
    static var aiProviderDeepSeek: String { tr("settings.ai.provider.deepseek") }
    static var aiProviderOpenRouter: String { tr("settings.ai.provider.openrouter") }
    static var aiProviderCustom: String { tr("settings.ai.provider.custom") }
    static var aiProviderOpenAIKeyPlaceholder: String { tr("settings.ai.provider.openai.keyPlaceholder") }
    static var aiProviderDeepSeekKeyPlaceholder: String { tr("settings.ai.provider.deepseek.keyPlaceholder") }
    static var aiProviderOpenRouterKeyPlaceholder: String { tr("settings.ai.provider.openrouter.keyPlaceholder") }
    static var aiProviderCustomKeyPlaceholder: String { tr("settings.ai.provider.custom.keyPlaceholder") }
    static var aiCustomBaseURLPlaceholder: String { tr("settings.ai.customBaseURL.placeholder") }
    static var aiCustomBaseURLFooter: String { tr("settings.ai.customBaseURL.footer") }
    static var aiCustomBaseURLMissing: String { tr("settings.ai.customBaseURL.missing") }
    static var aiCustomModelPlaceholder: String { tr("settings.ai.customModel.placeholder") }
    static var aiCustomModelFooter: String { tr("settings.ai.customModel.footer") }
    static var aiModelOpenAI4oMiniDetail: String { tr("settings.ai.model.openai.4oMini") }
    static var aiModelOpenAI4oDetail: String { tr("settings.ai.model.openai.4o") }
    static var aiModelDeepSeekChatDetail: String { tr("settings.ai.model.deepseek.chat") }
    static var aiModelDeepSeekReasonerDetail: String { tr("settings.ai.model.deepseek.reasoner") }
    static var aiModelOpenRouterDetail: String { tr("settings.ai.model.openrouter") }
    static var aiModelCustomDetail: String { tr("settings.ai.model.custom") }
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
    static var settingsBackupReminderEnabled: String { tr("settings.backupReminder.enabled") }
    static var settingsBackupReminderFooter: String { tr("settings.backupReminder.footer") }
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

    // MARK: - Privacy

    static var privacyTitle: String { tr("privacy.title") }
    static var privacyIntro: String { tr("privacy.intro") }
    static var privacyDataCollectionTitle: String { tr("privacy.data.title") }
    static var privacyDataCollectionBody: String { tr("privacy.data.body") }
    static var privacyAITitle: String { tr("privacy.ai.title") }
    static var privacyAIBody: String { tr("privacy.ai.body") }
    static var privacyOCRTitle: String { tr("privacy.ocr.title") }
    static var privacyOCRBody: String { tr("privacy.ocr.body") }
    static var privacyStorageTitle: String { tr("privacy.storage.title") }
    static var privacyStorageBody: String { tr("privacy.storage.body") }
    static var privacyContactTitle: String { tr("privacy.contact.title") }
    static var privacyContactBody: String { tr("privacy.contact.body") }

    // MARK: - Account

    static var accountSignedOutTitle: String { tr("account.signedOut.title") }
    static var accountSignedOutMessage: String { tr("account.signedOut.message") }
    static var accountSignInWeChat: String { tr("account.signIn.wechat") }
    static var accountSignInApple: String { tr("account.signIn.apple") }
    static var accountAppleUnavailable: String { tr("account.apple.unavailable") }
    static var accountSignOut: String { tr("account.signOut") }
    static var accountSignInFailed: String { tr("account.signIn.failed") }
    static var accountProviderApple: String { tr("account.provider.apple") }
    static var accountProviderWeChat: String { tr("account.provider.wechat") }
    static var accountAppleCancelled: String { tr("account.apple.cancelled") }
    static var accountAppleMissingCredential: String { tr("account.apple.missingCredential") }
    static var accountAppleMissingToken: String { tr("account.apple.missingToken") }
    static var accountWeChatNotConfigured: String { tr("account.wechat.notConfigured") }
    static var accountWeChatSDKNotLinked: String { tr("account.wechat.sdkNotLinked") }
    static var accountWeChatNotInstalled: String { tr("account.wechat.notInstalled") }
    static var accountWeChatMissingCode: String { tr("account.wechat.missingCode") }
    static var accountWeChatBackendRequired: String { tr("account.wechat.backendRequired") }
    static func accountWeChatBackendFailed(_ message: String) -> String { tf("account.wechat.backendFailed", message) }
    static func accountKeychainError(_ code: OSStatus) -> String { tf("account.keychain.error", code) }
    static var accountInvalidData: String { tr("account.invalidData") }

    // MARK: - Apkg

    static var apkgExportEmpty: String { tr("apkg.export.empty") }
    static func apkgExportFailed(_ message: String) -> String { tf("apkg.export.failed", message) }
    static var apkgExportZipFailed: String { tr("apkg.export.zipFailed") }

    // MARK: - Decks

    static var deckDefaultName: String { tr("deck.default.name") }
    static var deckDefaultDetail: String { tr("deck.default.detail") }
    static var deckSection: String { tr("deck.section") }
    static var deckSectionFooter: String { tr("deck.section.footer") }
    static var deckTarget: String { tr("deck.target") }
    static var deckManage: String { tr("deck.manage") }
    static var deckLoading: String { tr("deck.loading") }
    static func deckLabelWithCount(_ name: String, count: Int) -> String {
        tf("deck.labelWithCount", name, count)
    }
    static var deckStoreTitle: String { tr("deck.store.title") }
    static var deckMyDecks: String { tr("deck.myDecks") }
    static var deckEmpty: String { tr("deck.empty") }
    static var deckImportDeckSection: String { tr("deck.import.deckSection") }
    static var deckImportDeckFooter: String { tr("deck.import.deckFooter") }
    static var deckSingleDeckSection: String { tr("deck.singleDeck.section") }
    static func deckSingleDeckFooter(_ name: String) -> String { tf("deck.singleDeck.footer", name) }
    static var deckSingleDeckNoSelection: String { tr("deck.singleDeck.noSelection") }
    static var deckActionsSection: String { tr("deck.actions.section") }
    static func deckActionsFooter(_ count: Int) -> String { tf("deck.actions.footer", count) }
    static var deckActionsImportFooter: String { tr("deck.actions.importFooter") }
    static var deckSelectAll: String { tr("deck.selectAll") }
    static var deckDeselectAll: String { tr("deck.deselectAll") }
    static var deckImportNeedSingleSelection: String { tr("deck.import.needSingleSelection") }
    static var deckImportNeedSelectionForNoDeckInfo: String { tr("deck.import.needSelectionForNoDeckInfo") }
    static func deckImportIntoSelectedDecksResult(deckCount: Int, added: Int, updated: Int) -> String {
        tf("deck.import.intoSelectedDecksResult", deckCount, added, updated)
    }
    static var deckImportModeTitle: String { tr("deck.importMode.title") }
    static var deckImportModeReplace: String { tr("deck.importMode.replace") }
    static func deckImportModeMessage(_ deckName: String) -> String { tf("deck.importMode.message", deckName) }
    static func deckImportReplaceDeckResult(_ name: String, count: Int) -> String {
        tf("deck.import.replaceDeckResult", name, count)
    }
    static var deckExportNeedSelection: String { tr("deck.export.needSelection") }
    static func deckExportCheckedJSONResult(_ count: Int) -> String { tf("deck.export.checkedJSONResult", count) }
    static var deckAppBackupSection: String { tr("deck.appBackup.section") }
    static var deckAppBackupFooter: String { tr("deck.appBackup.footer") }
    static var deckBackupSection: String { tr("deck.backup.section") }
    static func deckBackupFooter(_ count: Int) -> String { tf("deck.backup.footer", count) }
    static var deckImportPack: String { tr("deck.import.pack") }
    static var deckImportApkg: String { tr("deck.import.apkg") }
    static var deckQuickImportJSON: String { tr("deck.quick.importJSON") }
    static var deckQuickExportDeckJSON: String { tr("deck.quick.exportDeckJSON") }
    static var deckQuickImportApkg: String { tr("deck.quick.importApkg") }
    static var deckQuickExportDeckApkg: String { tr("deck.quick.exportDeckApkg") }
    static var deckAppSaveBackup: String { tr("deck.app.saveBackup") }
    static var deckAppRestoreBackup: String { tr("deck.app.restoreBackup") }
    static var deckAppExportAllApkg: String { tr("deck.app.exportAllApkg") }
    static var deckQuickImportPack: String { tr("deck.quick.importPack") }
    static var deckQuickExportJSON: String { tr("deck.quick.exportJSON") }
    static var deckQuickImportBackup: String { tr("deck.quick.importBackup") }
    static var deckQuickExportApkg: String { tr("deck.quick.exportApkg") }
    static var deckPreparingExport: String { tr("deck.preparingExport") }
    static var deckInstalled: String { tr("deck.preset.installed") }
    static var deckInstallComplete: String { tr("deck.install.complete") }
    static func deckInstallWithCards(_ name: String, count: Int) -> String {
        tf("deck.install.withCards", name, count)
    }
    static func deckInstallEmpty(_ name: String) -> String {
        tf("deck.install.empty", name)
    }
    static var deckCreateTitle: String { tr("deck.create.title") }
    static var deckEditTitle: String { tr("deck.edit.title") }
    static var deckEdit: String { tr("deck.edit") }
    static var deckEditFailed: String { tr("deck.edit.failed") }
    static var deckSave: String { tr("deck.save") }
    static var deckNamePlaceholder: String { tr("deck.name.placeholder") }
    static var deckDetailPlaceholder: String { tr("deck.detail.placeholder") }
    static var deckUntitled: String { tr("deck.untitled") }
    static var deckDelete: String { tr("deck.delete") }
    static var deckDeleteFailed: String { tr("deck.delete.failed") }
    static var deckClear: String { tr("deck.clear") }
    static var deckClearTitle: String { tr("deck.clear.title") }
    static func deckClearMessage(_ name: String) -> String { tf("deck.clear.message", name) }
    static var deckClearComplete: String { tr("deck.clear.complete") }
    static var deckClearFailed: String { tr("deck.clear.failed") }
    static func deckClearResult(_ name: String, count: Int) -> String {
        tf("deck.clear.result", name, count)
    }
    static var deckImportComplete: String { tr("deck.import.complete") }
    static var deckImportFailed: String { tr("deck.import.failed") }
    static var deckImportInvalidJSON: String { tr("deck.import.invalidJSON") }
    static var deckImportEmptyFile: String { tr("deck.import.emptyFile") }
    static var deckImportWrongFormatBackup: String { tr("deck.import.wrongFormatBackup") }
    static var deckImportWrongFormatPack: String { tr("deck.import.wrongFormatPack") }
    static var deckImportWrongFormatHintPack: String { tr("deck.import.wrongFormatHintPack") }
    static var deckImportWrongFormatHintBackup: String { tr("deck.import.wrongFormatHintBackup") }
    static func deckImportPackResult(_ name: String, count: Int) -> String {
        tf("deck.import.packResult", name, count)
    }
    static func deckImportApkgResult(_ name: String, count: Int) -> String {
        tf("deck.import.apkgResult", name, count)
    }
    static func deckImportApkgMultiResult(deckCount: Int, cardCount: Int) -> String {
        tf("deck.import.apkgMultiResult", deckCount, cardCount)
    }
    static var deckImportFallbackUnmappedName: String { tr("deck.import.fallback.unmappedName") }
    static var deckImportFallbackIncompleteName: String { tr("deck.import.fallback.incompleteName") }
    static var deckImportEmptyCardPlaceholder: String { tr("deck.import.emptyCardPlaceholder") }
    static var deckImportMissingBackPlaceholder: String { tr("deck.import.missingBackPlaceholder") }
    static func deckImportApkgUnmappedResult(_ name: String, count: Int) -> String {
        tf("deck.import.apkgUnmappedResult", name, count)
    }
    static func deckImportApkgIncompleteResult(_ name: String, count: Int) -> String {
        tf("deck.import.apkgIncompleteResult", name, count)
    }
    static func deckImportDeckJSONResult(_ name: String, added: Int, updated: Int) -> String {
        tf("deck.import.deckJSONResult", name, added, updated)
    }
    static var deckFilterAll: String { tr("deck.filter.all") }
    static func libraryReviewDeck(_ name: String, count: Int) -> String {
        tf("library.reviewDeck", name, count)
    }
    static var libraryViewFlat: String { tr("library.view.flat") }
    static var libraryViewGrouped: String { tr("library.view.grouped") }
    static var libraryFlatListHint: String { tr("library.flatList.hint") }
    static var libraryFilterTitle: String { tr("library.filter.title") }
    static var libraryFilterAll: String { tr("library.filter.all") }
    static var libraryFilterDue: String { tr("library.filter.due") }
    static var libraryFilterDefinition: String { tr("library.filter.definition") }
    static var libraryFilterCloze: String { tr("library.filter.cloze") }
    static var libraryFilterMenu: String { tr("library.filter.menu") }
    static var libraryEmptyGoCreate: String { tr("library.empty.goCreate") }
    static var deckDownload: String { tr("deck.download.starter") }
    static func deckCardCount(_ count: Int) -> String {
        tf("deck.preset.starterCount", count)
    }
    static var deckErrorCannotDeleteDefault: String { tr("deck.error.cannotDeleteDefault") }
    static var deckErrorInvalidName: String { tr("deck.error.invalidName") }
    static var deckOpenSourceSection: String { tr("deck.openSource.section") }
    static var deckCatalogTitle: String { tr("deck.catalog.title") }
    static var deckCatalogSubtitle: String { tr("deck.catalog.subtitle") }
    static var deckOpenSourceFooter: String { tr("deck.openSource.footer") }
    static var deckCommunitySection: String { tr("deck.community.section") }
    static var deckCommunityFooter: String { tr("deck.community.footer") }
    static var deckCommunityOpenAnkiWeb: String { tr("deck.community.openAnkiWeb") }
    static var deckCommunityImportGuide: String { tr("deck.community.importGuide") }
    static var deckCommunityImportGuideTitle: String { tr("deck.community.importGuide.title") }
    static var deckCommunityImportGuideBody: String { tr("deck.community.importGuide.body") }
    static var deckCommunityImportNow: String { tr("deck.community.importNow") }
    static func deckCommunityEstimatedCards(_ count: Int) -> String {
        tf("deck.community.estimatedCards", count)
    }
    static func deckRemoteLicense(_ license: String) -> String {
        tf("deck.remote.license", license)
    }
    static var deckRemoteViewSource: String { tr("deck.remote.viewSource") }
    static var deckRemoteNGSLName: String { tr("deck.remote.ngsl.name") }
    static var deckRemoteNGSLDetail: String { tr("deck.remote.ngsl.detail") }
    static var deckRemoteNAWLName: String { tr("deck.remote.nawl.name") }
    static var deckRemoteNAWLDetail: String { tr("deck.remote.nawl.detail") }
    static var deckRemoteTOEFLName: String { tr("deck.remote.toefl.name") }
    static var deckRemoteTOEFLDetail: String { tr("deck.remote.toefl.detail") }
    static var deckCommunityIELTS4000Name: String { tr("deck.community.ielts4000.name") }
    static var deckCommunityIELTS4000Detail: String { tr("deck.community.ielts4000.detail") }
    static var deckCommunityEnglish60kName: String { tr("deck.community.english60k.name") }
    static var deckCommunityEnglish60kDetail: String { tr("deck.community.english60k.detail") }
    static var deckCommunityAdvancedVocabName: String { tr("deck.community.advancedVocab.name") }
    static var deckCommunityAdvancedVocabDetail: String { tr("deck.community.advancedVocab.detail") }
    static var deckCommunityGRESearchName: String { tr("deck.community.greSearch.name") }
    static var deckCommunityGRESearchDetail: String { tr("deck.community.greSearch.detail") }
    static var deckCommunityTOEFLSearchName: String { tr("deck.community.toeflSearch.name") }
    static var deckCommunityTOEFLSearchDetail: String { tr("deck.community.toeflSearch.detail") }
    static var deckDownloading: String { tr("deck.downloading") }
    static var deckDownloadFailed: String { tr("deck.download.failed") }
    static var deckDownloadInvalidResponse: String { tr("deck.download.invalidResponse") }
    static var deckDownloadEmptyPack: String { tr("deck.download.emptyPack") }
    static func deckDownloadNetworkFailed(_ message: String) -> String {
        tf("deck.download.networkFailed", message)
    }
    static var apkgImportInvalid: String { tr("apkg.import.invalid") }
    static var apkgImportMissingCollection: String { tr("apkg.import.missingCollection") }
    static func apkgImportFailed(_ message: String) -> String { tf("apkg.import.failed", message) }
    static var apkgImportEmpty: String { tr("apkg.import.empty") }
    static var deckExtensionFooter: String { tr("deck.extension.footer") }
    static var deckExtensionEmptyCatalog: String { tr("deck.extension.emptyCatalog") }
    static var deckExtensionEmptyCatalogHint: String { tr("deck.extension.emptyCatalogHint") }
    static func deckImportProgress(current: Int, total: Int) -> String {
        tf("deck.import.progress", current, total)
    }
    static var deckStatisticsOverview: String { tr("deck.statistics.overview") }
    static var deckStatisticsTotal: String { tr("deck.statistics.total") }
    static var deckStatisticsDue: String { tr("deck.statistics.due") }
    static var deckStatisticsNew: String { tr("deck.statistics.new") }
    static var deckStatisticsLearned: String { tr("deck.statistics.learned") }
    static var deckStatisticsMastery: String { tr("deck.statistics.mastery") }
    static func deckStatisticsMasteryValue(_ rate: Double) -> String {
        tf("deck.statistics.masteryValue", Int(rate * 100))
    }

    // MARK: - Notifications

    static var backupReminderTitle: String { tr("backup.reminder.title") }
    static var backupReminderBody: String { tr("backup.reminder.body") }

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

import Foundation
import UserNotifications

struct ShareImportPayload: Equatable {
    let sentence: String
    let selectedWord: String?
    let source: ImportSource

    init(sentence: String, selectedWord: String? = nil, source: ImportSource = .shareExtension) {
        self.sentence = sentence
        self.selectedWord = selectedWord
        self.source = source
    }
}

enum ImportSource: Equatable {
    case shareExtension
    case clipboard
}

extension ShareImportPayload {
    var bannerMessage: String {
        let hasSentence = !sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasWords = selectedWord?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false

        switch source {
        case .clipboard:
            if hasSentence && hasWords { return L10n.importClipboardBoth }
            if hasWords { return L10n.importClipboardWord }
            return L10n.importClipboardSentence
        case .shareExtension:
            if hasWords { return L10n.importShareBoth }
            return L10n.importShareSentence
        }
    }
}

enum ShareImportStore {
    static let appGroupID = "group.com.vocabflow.app1"
    static let createURLString = "vocabflow://create"
    private static let payloadFileName = "share-import.json"
    private static let draftsFileName = "share-drafts.json"
    private static let generationJobFileName = "share-generation-job.json"

    private struct StoredPayload: Codable {
        let sentence: String
        let selectedWord: String?
        let pending: Bool
    }

    private struct StoredCardDraft: Codable {
        let word: String
        let phonetic: String?
        let sentence: String
        let cardTypeRaw: String
        let front: String
        let back: String

        init(from draft: GeneratedCardDraft) {
            word = draft.word
            phonetic = draft.phonetic
            sentence = draft.sentence
            cardTypeRaw = draft.cardType.rawValue
            front = draft.front
            back = draft.back
        }

        enum CodingKeys: String, CodingKey {
            case word, phonetic, sentence, cardTypeRaw, front, back
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            word = try container.decode(String.self, forKey: .word)
            phonetic = try container.decodeIfPresent(String.self, forKey: .phonetic)
            sentence = try container.decode(String.self, forKey: .sentence)
            cardTypeRaw = try container.decode(String.self, forKey: .cardTypeRaw)
            front = try container.decode(String.self, forKey: .front)
            back = try container.decode(String.self, forKey: .back)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(word, forKey: .word)
            try container.encode(phonetic, forKey: .phonetic)
            try container.encode(sentence, forKey: .sentence)
            try container.encode(cardTypeRaw, forKey: .cardTypeRaw)
            try container.encode(front, forKey: .front)
            try container.encode(back, forKey: .back)
        }
    }

    private struct StoredDraftsPayload: Codable {
        let drafts: [StoredCardDraft]
        let pending: Bool
    }

    private enum GenerationJobStatus: String, Codable {
        case pending
        case processing
    }

    private struct StoredGenerationJob: Codable {
        let sentence: String
        let words: [String]
        var status: GenerationJobStatus
    }

    private static var payloadURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(payloadFileName)
    }

    private static var draftsURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(draftsFileName)
    }

    private static var generationJobURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(generationJobFileName)
    }

    static func save(sentence: String, selectedWord: String? = nil) {
        let payload = StoredPayload(
            sentence: sentence,
            selectedWord: selectedWord,
            pending: true
        )
        guard let url = payloadURL,
              let data = try? JSONEncoder().encode(payload) else {
            return
        }
        try? data.write(to: url, options: .atomic)
    }

    static func consumePendingImport() -> ShareImportPayload? {
        guard let url = payloadURL,
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(StoredPayload.self, from: data),
              payload.pending else {
            return nil
        }

        let sentence = payload.sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty else {
            clear()
            return nil
        }

        clear()
        return ShareImportPayload(
            sentence: sentence,
            selectedWord: payload.selectedWord?.isEmpty == false ? payload.selectedWord : nil
        )
    }

    static func clear() {
        guard let url = payloadURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func saveGeneratedDrafts(_ drafts: [GeneratedCardDraft]) {
        let stored = drafts.map { StoredCardDraft(from: $0) }
        let payload = StoredDraftsPayload(drafts: stored, pending: true)
        guard let url = draftsURL,
              let data = try? JSONEncoder().encode(payload) else {
            return
        }
        try? data.write(to: url, options: .atomic)
    }

    static func consumePendingDrafts() -> [GeneratedCardDraft]? {
        guard let url = draftsURL,
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(StoredDraftsPayload.self, from: data),
              payload.pending,
              !payload.drafts.isEmpty else {
            return nil
        }

        clearDrafts()
        return payload.drafts.compactMap { stored in
            guard let type = CardType(rawValue: stored.cardTypeRaw) else { return nil }
            return GeneratedCardDraft(
                word: stored.word,
                phonetic: stored.phonetic,
                sentence: stored.sentence,
                cardType: type,
                front: stored.front,
                back: stored.back,
                contextNote: nil
            )
        }
    }

    static func clearDrafts() {
        guard let url = draftsURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func savePendingGenerationJob(sentence: String, words: [String]) {
        let job = StoredGenerationJob(
            sentence: sentence,
            words: words,
            status: .pending
        )
        guard let url = generationJobURL,
              let data = try? JSONEncoder().encode(job) else {
            return
        }
        try? data.write(to: url, options: .atomic)
    }

    static func claimPendingGenerationJob() -> (sentence: String, words: [String])? {
        guard let url = generationJobURL,
              let data = try? Data(contentsOf: url),
              var job = try? JSONDecoder().decode(StoredGenerationJob.self, from: data) else {
            return nil
        }

        guard job.status == .pending else {
            return nil
        }

        job.status = .processing
        guard let updated = try? JSONEncoder().encode(job) else { return nil }
        try? updated.write(to: url, options: .atomic)

        let sentence = job.sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = job.words
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !sentence.isEmpty, !words.isEmpty else {
            clearGenerationJob()
            return nil
        }

        return (sentence, words)
    }

    static func clearGenerationJob() {
        guard let url = generationJobURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func resetStaleProcessingJob() {
        guard let url = generationJobURL,
              let data = try? Data(contentsOf: url),
              var job = try? JSONDecoder().decode(StoredGenerationJob.self, from: data),
              job.status == .processing else {
            return
        }

        job.status = .pending
        guard let updated = try? JSONEncoder().encode(job) else { return }
        try? updated.write(to: url, options: .atomic)
    }

    static var hasPendingGenerationJob: Bool {
        guard let url = generationJobURL,
              let data = try? Data(contentsOf: url),
              let job = try? JSONDecoder().decode(StoredGenerationJob.self, from: data) else {
            return false
        }
        return job.status == .pending || job.status == .processing
    }
}

enum ShareExtensionNotifier {
    private static let notificationPrefix = "vocabflow-share"

    static func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        @unknown default:
            return false
        }
    }

    static func scheduleGeneratingNotification(completion: ((Bool) -> Void)? = nil) {
        scheduleNotification(
            identifier: "\(notificationPrefix).generating",
            body: L10n.notificationGenerating,
            completion: completion
        )
    }

    static func scheduleImportReadyNotification(
        cardCount: Int? = nil,
        completion: ((Bool) -> Void)? = nil
    ) {
        let body: String
        if let cardCount, cardCount > 0 {
            body = L10n.notificationReady(cardCount)
        } else {
            body = L10n.notificationReadyGeneric
        }

        scheduleNotification(
            identifier: "\(notificationPrefix).ready",
            body: body,
            completion: completion
        )
    }

    static func scheduleCardsSavedNotification(
        cardCount: Int,
        completion: ((Bool) -> Void)? = nil
    ) {
        scheduleNotification(
            identifier: "\(notificationPrefix).saved",
            body: L10n.notificationSaved(cardCount),
            completion: completion
        )
    }

    static func scheduleFailureNotification(
        message: String,
        completion: ((Bool) -> Void)? = nil
    ) {
        scheduleNotification(
            identifier: "\(notificationPrefix).failure",
            body: L10n.notificationFailed(message),
            completion: completion
        )
    }

    private static func scheduleNotification(
        identifier: String,
        body: String,
        completion: ((Bool) -> Void)? = nil
    ) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else {
                DispatchQueue.main.async {
                    completion?(false)
                }
                return
            }

            let content = UNMutableNotificationContent()
            content.title = "VocabFlow"
            content.body = body
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: trigger
            )

            UNUserNotificationCenter.current().add(request) { error in
                DispatchQueue.main.async {
                    completion?(error == nil)
                }
            }
        }
    }
}

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
        let sentence: String
        let cardTypeRaw: String
        let front: String
        let back: String
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
        let stored = drafts.map {
            StoredCardDraft(
                word: $0.word,
                sentence: $0.sentence,
                cardTypeRaw: $0.cardType.rawValue,
                front: $0.front,
                back: $0.back
            )
        }
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
            body: "正在后台生成卡片，完成后会通知你",
            completion: completion
        )
    }

    static func scheduleImportReadyNotification(
        cardCount: Int? = nil,
        completion: ((Bool) -> Void)? = nil
    ) {
        let body: String
        if let cardCount, cardCount > 0 {
            body = "已生成 \(cardCount) 张卡片，打开 VocabFlow 预览并保存"
        } else {
            body = "分享内容已保存，点击继续制卡"
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
            body: "已保存 \(cardCount) 张卡片到词库，可以开始复习",
            completion: completion
        )
    }

    static func scheduleFailureNotification(
        message: String,
        completion: ((Bool) -> Void)? = nil
    ) {
        scheduleNotification(
            identifier: "\(notificationPrefix).failure",
            body: "生成失败：\(message)",
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

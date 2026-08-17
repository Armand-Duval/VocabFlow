import Foundation
import UserNotifications

struct ShareImportPayload: Equatable {
    let sentence: String
    let selectedWord: String?
    let sourceHint: String?
    let sourceImagePath: String?
    let source: ImportSource

    init(
        sentence: String,
        selectedWord: String? = nil,
        sourceHint: String? = nil,
        sourceImagePath: String? = nil,
        source: ImportSource = .shareExtension
    ) {
        self.sentence = sentence
        self.selectedWord = selectedWord
        self.sourceHint = sourceHint
        self.sourceImagePath = sourceImagePath
        self.source = source
    }
}

struct ShareInboxPayload: Equatable, Codable {
    enum Kind: String, Codable, Equatable {
        case text
        case image
    }

    let kind: Kind
    let text: String?
    /// App Group relative path, e.g. `share-inbox/{uuid}.heic`. Not a decoded bitmap.
    let relativePath: String?
}

enum ImportSource: Equatable {
    case shareExtension
    case clipboard
}

struct PendingShareGenerationJob: Equatable {
    let sentence: String
    let words: [String]
    let sourceHint: String?
    let sourceImagePath: String?
    let deckID: UUID?
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
    static let appGroupID = "group.com.knowellcards.app"
    static let createURLString = "knowell://create"
    static let inboxFolderName = "share-inbox"
    private static let payloadFileName = "share-import.json"
    private static let inboxManifestName = "share-inbox.json"
    private static let draftsFileName = "share-drafts.json"
    private static let generationJobFileName = "share-generation-job.json"
    private static let generationJobsDirectoryName = "share-generation-jobs"
    private static let triageFileName = "pending-triage.json"

    private struct StoredPayload: Codable {
        let sentence: String
        let selectedWord: String?
        let sourceHint: String?
        let sourceImagePath: String?
        let pending: Bool

        enum CodingKeys: String, CodingKey {
            case sentence, selectedWord, sourceHint, sourceImagePath, pending
        }

        init(
            sentence: String,
            selectedWord: String?,
            sourceHint: String? = nil,
            sourceImagePath: String? = nil,
            pending: Bool
        ) {
            self.sentence = sentence
            self.selectedWord = selectedWord
            self.sourceHint = sourceHint
            self.sourceImagePath = sourceImagePath
            self.pending = pending
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            sentence = try container.decode(String.self, forKey: .sentence)
            selectedWord = try container.decodeIfPresent(String.self, forKey: .selectedWord)
            sourceHint = try container.decodeIfPresent(String.self, forKey: .sourceHint)
            sourceImagePath = try container.decodeIfPresent(String.self, forKey: .sourceImagePath)
            pending = try container.decode(Bool.self, forKey: .pending)
        }
    }

    private struct StoredCardDraft: Codable {
        let word: String
        let phonetic: String?
        let sentence: String
        let cardTypeRaw: String
        let front: String
        let back: String
        let contextNote: String?
        let usageNote: String?
        let etymology: String?
        let synonyms: String?
        let antonyms: String?
        let paraphrases: String?
        let sourceAttribution: String?
        let sourceImagePath: String?
        let isSelected: Bool

        init(from draft: GeneratedCardDraft) {
            word = draft.word
            phonetic = draft.phonetic
            sentence = draft.sentence
            cardTypeRaw = draft.cardType.rawValue
            front = draft.front
            back = draft.back
            contextNote = draft.contextNote
            usageNote = draft.usageNote
            etymology = draft.etymology
            synonyms = draft.synonyms
            antonyms = draft.antonyms
            paraphrases = draft.paraphrases
            sourceAttribution = draft.sourceAttribution
            sourceImagePath = draft.sourceImagePath
            isSelected = draft.isSelected
        }

        enum CodingKeys: String, CodingKey {
            case word, phonetic, sentence, cardTypeRaw, front, back, contextNote
            case usageNote, etymology, synonyms, antonyms, paraphrases
            case sourceAttribution, sourceImagePath, isSelected
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            word = try container.decode(String.self, forKey: .word)
            phonetic = try container.decodeIfPresent(String.self, forKey: .phonetic)
            sentence = try container.decode(String.self, forKey: .sentence)
            cardTypeRaw = try container.decode(String.self, forKey: .cardTypeRaw)
            front = try container.decode(String.self, forKey: .front)
            back = try container.decode(String.self, forKey: .back)
            contextNote = try container.decodeIfPresent(String.self, forKey: .contextNote)
            usageNote = try container.decodeIfPresent(String.self, forKey: .usageNote)
            etymology = try container.decodeIfPresent(String.self, forKey: .etymology)
            synonyms = try container.decodeIfPresent(String.self, forKey: .synonyms)
            antonyms = try container.decodeIfPresent(String.self, forKey: .antonyms)
            paraphrases = try container.decodeIfPresent(String.self, forKey: .paraphrases)
            sourceAttribution = try container.decodeIfPresent(String.self, forKey: .sourceAttribution)
            sourceImagePath = try container.decodeIfPresent(String.self, forKey: .sourceImagePath)
            isSelected = try container.decodeIfPresent(Bool.self, forKey: .isSelected) ?? true
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(word, forKey: .word)
            try container.encode(phonetic, forKey: .phonetic)
            try container.encode(sentence, forKey: .sentence)
            try container.encode(cardTypeRaw, forKey: .cardTypeRaw)
            try container.encode(front, forKey: .front)
            try container.encode(back, forKey: .back)
            try container.encodeIfPresent(contextNote, forKey: .contextNote)
            try container.encodeIfPresent(usageNote, forKey: .usageNote)
            try container.encodeIfPresent(etymology, forKey: .etymology)
            try container.encodeIfPresent(synonyms, forKey: .synonyms)
            try container.encodeIfPresent(antonyms, forKey: .antonyms)
            try container.encodeIfPresent(paraphrases, forKey: .paraphrases)
            try container.encodeIfPresent(sourceAttribution, forKey: .sourceAttribution)
            try container.encodeIfPresent(sourceImagePath, forKey: .sourceImagePath)
            try container.encode(isSelected, forKey: .isSelected)
        }

        func makeDraft() -> GeneratedCardDraft? {
            guard let type = CardType(rawValue: cardTypeRaw) else { return nil }
            return GeneratedCardDraft(
                word: word,
                phonetic: phonetic,
                sentence: sentence,
                cardType: type,
                front: front,
                back: back,
                contextNote: contextNote,
                usageNote: usageNote,
                etymology: etymology,
                synonyms: synonyms,
                antonyms: antonyms,
                paraphrases: paraphrases,
                sourceAttribution: sourceAttribution,
                sourceImagePath: sourceImagePath,
                isSelected: isSelected
            )
        }
    }

    struct PersistedTriageBatch: Codable, Equatable {
        let id: UUID
        let deckID: UUID
        let drafts: [GeneratedCardDraft]
        let cursor: Int

        init(id: UUID, deckID: UUID, drafts: [GeneratedCardDraft], cursor: Int = 0) {
            self.id = id
            self.deckID = deckID
            self.drafts = drafts
            self.cursor = cursor
        }

        private enum CodingKeys: String, CodingKey {
            case id, deckID, drafts, cursor
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            deckID = try container.decode(UUID.self, forKey: .deckID)
            let stored = try container.decode([StoredCardDraft].self, forKey: .drafts)
            drafts = stored.compactMap { $0.makeDraft() }
            cursor = try container.decodeIfPresent(Int.self, forKey: .cursor) ?? 0
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(deckID, forKey: .deckID)
            try container.encode(drafts.map { StoredCardDraft(from: $0) }, forKey: .drafts)
            try container.encode(cursor, forKey: .cursor)
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
        let id: UUID
        let sentence: String
        let words: [String]
        let sourceHint: String?
        let sourceImagePath: String?
        let deckID: UUID?
        var status: GenerationJobStatus

        enum CodingKeys: String, CodingKey {
            case id, sentence, words, sourceHint, sourceImagePath, deckID, status
        }

        init(
            id: UUID = UUID(),
            sentence: String,
            words: [String],
            sourceHint: String? = nil,
            sourceImagePath: String? = nil,
            deckID: UUID? = nil,
            status: GenerationJobStatus
        ) {
            self.id = id
            self.sentence = sentence
            self.words = words
            self.sourceHint = sourceHint
            self.sourceImagePath = sourceImagePath
            self.deckID = deckID
            self.status = status
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            sentence = try container.decode(String.self, forKey: .sentence)
            words = try container.decode([String].self, forKey: .words)
            sourceHint = try container.decodeIfPresent(String.self, forKey: .sourceHint)
            sourceImagePath = try container.decodeIfPresent(String.self, forKey: .sourceImagePath)
            deckID = try container.decodeIfPresent(UUID.self, forKey: .deckID)
            status = try container.decodeIfPresent(GenerationJobStatus.self, forKey: .status) ?? .pending
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(sentence, forKey: .sentence)
            try container.encode(words, forKey: .words)
            try container.encodeIfPresent(sourceHint, forKey: .sourceHint)
            try container.encodeIfPresent(sourceImagePath, forKey: .sourceImagePath)
            try container.encodeIfPresent(deckID, forKey: .deckID)
            try container.encode(status, forKey: .status)
        }

        func makePending() -> PendingShareGenerationJob? {
            let sentence = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            let words = words
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !sentence.isEmpty, !words.isEmpty else { return nil }
            return PendingShareGenerationJob(
                sentence: sentence,
                words: words,
                sourceHint: sourceHint,
                sourceImagePath: sourceImagePath,
                deckID: deckID
            )
        }
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

    static func inboxDirectory() throws -> URL {
        guard let group = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let folder = group.appendingPathComponent(inboxFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func inboxFileURL(relativePath: String) -> URL? {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains(".."),
              trimmed.hasPrefix(inboxFolderName + "/") else {
            return nil
        }
        return FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(trimmed)
    }

    /// Copy bytes on disk. Do not decode the image in the extension.
    static func importInboxFile(from sourceURL: URL, fileExtension: String) throws -> String {
        let ext = fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        let safeExt = ext.isEmpty ? "img" : ext
        let name = "\(UUID().uuidString).\(safeExt)"
        let destination = try inboxDirectory().appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return "\(inboxFolderName)/\(name)"
    }

    static func importInboxData(_ data: Data, fileExtension: String) throws -> String {
        let ext = fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        let safeExt = ext.isEmpty ? "img" : ext
        let name = "\(UUID().uuidString).\(safeExt)"
        let destination = try inboxDirectory().appendingPathComponent(name)
        try data.write(to: destination, options: .atomic)
        return "\(inboxFolderName)/\(name)"
    }

    static func saveInbox(_ payload: ShareInboxPayload) {
        guard let group = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ),
              let data = try? JSONEncoder().encode(payload) else {
            return
        }
        let url = group.appendingPathComponent(inboxManifestName)
        try? data.write(to: url, options: .atomic)
    }

    static func consumeInbox() -> ShareInboxPayload? {
        guard let group = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else {
            return nil
        }
        let url = group.appendingPathComponent(inboxManifestName)
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(ShareInboxPayload.self, from: data) else {
            return nil
        }
        try? FileManager.default.removeItem(at: url)
        return payload
    }

    static func removeInboxFile(_ relativePath: String?) {
        guard let relativePath,
              let url = inboxFileURL(relativePath: relativePath) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func save(
        sentence: String,
        selectedWord: String? = nil,
        sourceHint: String? = nil,
        sourceImagePath: String? = nil
    ) {
        let payload = StoredPayload(
            sentence: sentence,
            selectedWord: selectedWord,
            sourceHint: sourceHint,
            sourceImagePath: sourceImagePath,
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
        let hint = payload.sourceHint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let imagePath = payload.sourceImagePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return ShareImportPayload(
            sentence: sentence,
            selectedWord: payload.selectedWord?.isEmpty == false ? payload.selectedWord : nil,
            sourceHint: hint.isEmpty ? nil : hint,
            sourceImagePath: imagePath.isEmpty ? nil : imagePath,
            source: .shareExtension
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
        return payload.drafts.compactMap { $0.makeDraft() }
    }

    static func clearDrafts() {
        guard let url = draftsURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static var triageURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(triageFileName)
    }

    static func saveTriageBatches(_ batches: [PersistedTriageBatch]) {
        guard let url = triageURL else { return }
        if batches.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        guard let data = try? JSONEncoder().encode(batches) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func loadTriageBatches() -> [PersistedTriageBatch] {
        guard let url = triageURL,
              let data = try? Data(contentsOf: url),
              let batches = try? JSONDecoder().decode([PersistedTriageBatch].self, from: data) else {
            return []
        }
        return batches.filter { !$0.drafts.isEmpty }
    }

    static func savePendingGenerationJob(
        sentence: String,
        words: [String],
        sourceHint: String? = nil,
        sourceImagePath: String? = nil,
        deckID: UUID? = nil
    ) {
        let job = StoredGenerationJob(
            sentence: sentence,
            words: words,
            sourceHint: sourceHint,
            sourceImagePath: sourceImagePath,
            deckID: deckID,
            status: .pending
        )
        guard let directory = generationJobsDirectoryURL else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return
        }
        let url = directory.appendingPathComponent("\(job.id.uuidString).json")
        guard let data = try? JSONEncoder().encode(job) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Drain every queued share job (new directory + legacy single file).
    static func takeAllPendingGenerationJobs() -> [PendingShareGenerationJob] {
        var jobs: [PendingShareGenerationJob] = []
        jobs.append(contentsOf: takeLegacyGenerationJob())
        jobs.append(contentsOf: takeQueuedGenerationJobs())
        return jobs
    }

    static func clearGenerationJob() {
        if let url = generationJobURL {
            try? FileManager.default.removeItem(at: url)
        }
        if let directory = generationJobsDirectoryURL {
            try? FileManager.default.removeItem(at: directory)
        }
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
        if let url = generationJobURL,
           let data = try? Data(contentsOf: url),
           let job = try? JSONDecoder().decode(StoredGenerationJob.self, from: data),
           job.status == .pending || job.status == .processing {
            return true
        }
        guard let directory = generationJobsDirectoryURL else { return false }
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls.contains { $0.pathExtension.lowercased() == "json" }
    }

    private static var generationJobsDirectoryURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(generationJobsDirectoryName, isDirectory: true)
    }

    private static func takeLegacyGenerationJob() -> [PendingShareGenerationJob] {
        guard let url = generationJobURL,
              let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode(StoredGenerationJob.self, from: data) else {
            return []
        }
        try? FileManager.default.removeItem(at: url)
        guard let job = stored.makePending() else { return [] }
        return [job]
    }

    private static func takeQueuedGenerationJobs() -> [PendingShareGenerationJob] {
        guard let directory = generationJobsDirectoryURL else { return [] }
        let urls = ((try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? [])
        .filter { $0.pathExtension.lowercased() == "json" }
        .sorted { lhs, rhs in
            let left = (try? lhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let right = (try? rhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return left < right
        }

        var jobs: [PendingShareGenerationJob] = []
        for url in urls {
            defer { try? FileManager.default.removeItem(at: url) }
            guard let data = try? Data(contentsOf: url),
                  let stored = try? JSONDecoder().decode(StoredGenerationJob.self, from: data),
                  let job = stored.makePending() else {
                continue
            }
            jobs.append(job)
        }
        return jobs
    }
}

enum ShareExtensionNotifier {
    private static let notificationPrefix = "knowell-share"

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

    static func scheduleInboxHandoffNotification(completion: ((Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                break
            default:
                DispatchQueue.main.async {
                    completion?(false)
                }
                return
            }

            let content = UNMutableNotificationContent()
            content.title = L10n.brandName
            content.body = L10n.notificationShareInbox
            content.sound = .default
            content.userInfo = [
                "open": "create",
                "knowell": "share-inbox"
            ]
            content.interruptionLevel = .timeSensitive
            content.relevanceScore = 1

            let request = UNNotificationRequest(
                identifier: "\(notificationPrefix).inbox",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.15, repeats: false)
            )

            UNUserNotificationCenter.current().add(request) { error in
                DispatchQueue.main.async {
                    completion?(error == nil)
                }
            }
        }
    }

    /// Soft notice (no "failed" prefix) — e.g. all words already in deck.
    static func scheduleNoticeNotification(
        body: String,
        completion: ((Bool) -> Void)? = nil
    ) {
        scheduleNotification(
            identifier: "\(notificationPrefix).notice",
            body: body,
            completion: completion
        )
    }

    private static func scheduleNotification(
        identifier: String,
        body: String,
        delay: TimeInterval = 0.5,
        completion: ((Bool) -> Void)? = nil
    ) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                break
            default:
                DispatchQueue.main.async {
                    completion?(false)
                }
                return
            }

            let content = UNMutableNotificationContent()
            content.title = L10n.brandName
            content.body = body
            content.sound = .default
            content.userInfo = ["open": "create"]

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(delay, 0.1), repeats: false)
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

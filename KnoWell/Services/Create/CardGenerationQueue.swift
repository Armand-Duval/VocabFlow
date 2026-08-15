import Foundation
import SwiftUI
import SwiftData

@MainActor
final class CardGenerationQueue: ObservableObject {
    static let shared = CardGenerationQueue()

    private init() {
        pendingTriages = ShareImportStore.loadTriageBatches().map {
            ReadyPreview(
                id: $0.id,
                drafts: $0.drafts,
                deckID: $0.deckID,
                cursor: $0.cursor,
                skippedDuplicates: 0
            )
        }
    }

    enum JobKind: Equatable {
        case create
        case migrate
    }

    enum JobStatus: String {
        case queued
        case running
        case succeeded
        case failed
    }

    enum WordStatus: String {
        case pending
        case running
        case done
        case failed
        case skipped
    }

    struct WordItem: Identifiable, Equatable {
        let id: UUID
        let word: String
        let sentence: String
        var status: WordStatus

        init(word: String, sentence: String, status: WordStatus = .pending) {
            id = UUID()
            self.word = word
            self.sentence = sentence
            self.status = status
        }
    }

    struct Job: Identifiable, Equatable {
        let id: UUID
        let createdAt: Date
        let kind: JobKind
        let deckID: UUID
        let deckName: String?
        let sourceHint: String?
        let sourceImagePath: String?
        let sentencePreview: String
        let units: [OCRImportUnit]
        var status: JobStatus
        var completedBatches: Int
        var totalBatches: Int
        var skippedDuplicates: Int
        var words: [WordItem]
        var drafts: [GeneratedCardDraft]
        var errorMessage: String?
        var migrationBatches: [CardContentMigrationBatch]
        var migrationReport: CardContentMigrationReport?

        var progressFraction: Double {
            guard totalBatches > 0 else { return status == .succeeded ? 1 : 0 }
            return Double(completedBatches) / Double(totalBatches)
        }

        var isActive: Bool {
            status == .queued || status == .running
        }

        var displayTitle: String {
            kind == .migrate ? L10n.settingsMigrateCards : sentencePreview
        }
    }

    struct ReadyPreview: Equatable, Identifiable {
        let id: UUID
        var drafts: [GeneratedCardDraft]
        var deckID: UUID
        var cursor: Int
        var skippedDuplicates: Int
    }

    @Published private(set) var jobs: [Job] = []
    @Published private(set) var pendingTriages: [ReadyPreview] = []

    var readyPreview: ReadyPreview? { pendingTriages.first }

    var pendingTriageCardCount: Int {
        pendingTriages.reduce(0) { $0 + $1.drafts.count }
    }

    private var isProcessing = false
    private var migrationContext: ModelContext?

    enum MigrationEnqueueError: LocalizedError {
        case alreadyRunning

        var errorDescription: String? {
            switch self {
            case .alreadyRunning: L10n.settingsMigrateCardsAlreadyQueued
            }
        }
    }

    var activeJobs: [Job] {
        jobs.filter(\.isActive)
    }

    var hasActiveJobs: Bool {
        !activeJobs.isEmpty
    }

    var hasActiveMigrationJob: Bool {
        jobs.contains { $0.kind == .migrate && $0.isActive }
    }

    var activeSummary: String {
        let active = activeJobs
        guard let first = active.first else { return "" }
        if active.count == 1 {
            if first.status == .running, first.totalBatches > 0 {
                return L10n.generatingProgress(first.completedBatches, first.totalBatches)
            }
            return L10n.createQueueBannerOne
        }
        return L10n.createQueueBannerMany(active.count)
    }

    @discardableResult
    func enqueue(
        sentence: String,
        words: [String],
        deckID: UUID,
        deckName: String?,
        sourceHint: String?,
        sourceImagePath: String? = nil
    ) throws -> UUID {
        let prepared = try KimiCardGenerator.prepareGeneration(
            sentence: sentence,
            words: words,
            skipExistingInDeckID: deckID
        )

        var wordItems: [WordItem] = []
        for unit in prepared.units {
            for word in unit.words {
                wordItems.append(WordItem(word: word, sentence: unit.sentence))
            }
        }

        let preview = sentence
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(80)
        let job = Job(
            id: UUID(),
            createdAt: Date(),
            kind: .create,
            deckID: deckID,
            deckName: deckName,
            sourceHint: sourceHint,
            sourceImagePath: {
                let path = sourceImagePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return path.isEmpty ? nil : path
            }(),
            sentencePreview: String(preview),
            units: prepared.units,
            status: .queued,
            completedBatches: 0,
            totalBatches: prepared.batchCount,
            skippedDuplicates: prepared.skippedCount,
            words: wordItems,
            drafts: [],
            errorMessage: nil,
            migrationBatches: [],
            migrationReport: nil
        )
        jobs.insert(job, at: 0)
        processNextIfNeeded()
        return job.id
    }

    @discardableResult
    func enqueueMigration(
        in context: ModelContext,
        initialReport: CardContentMigrationReport,
        plan: CardContentMigrationPlan
    ) throws -> UUID {
        guard !hasActiveMigrationJob else {
            throw MigrationEnqueueError.alreadyRunning
        }

        var wordItems: [WordItem] = []
        var seen = Set<String>()
        for batch in plan.batches {
            for word in batch.words {
                let key = "\(word.lowercased())|\(batch.sentence)"
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                wordItems.append(WordItem(word: word, sentence: batch.sentence))
            }
        }

        migrationContext = context
        let job = Job(
            id: UUID(),
            createdAt: Date(),
            kind: .migrate,
            deckID: UUID(),
            deckName: nil,
            sourceHint: nil,
            sourceImagePath: nil,
            sentencePreview: L10n.settingsMigrateCards,
            units: [],
            status: .queued,
            completedBatches: 0,
            totalBatches: plan.batches.count,
            skippedDuplicates: 0,
            words: wordItems,
            drafts: [],
            errorMessage: nil,
            migrationBatches: plan.batches,
            migrationReport: initialReport
        )
        jobs.insert(job, at: 0)
        processNextIfNeeded()
        return job.id
    }

    func enqueueTriage(
        drafts: [GeneratedCardDraft],
        deckID: UUID,
        skippedDuplicates: Int = 0
    ) {
        let selected = drafts.filter(\.isSelected)
        let items = selected.isEmpty ? drafts : selected
        guard !items.isEmpty else { return }
        pendingTriages.append(
            ReadyPreview(
                id: UUID(),
                drafts: items,
                deckID: deckID,
                cursor: 0,
                skippedDuplicates: skippedDuplicates
            )
        )
        persistTriages()
    }

    func replaceCurrentTriage(
        drafts: [GeneratedCardDraft],
        deckID: UUID? = nil,
        cursor: Int = 0
    ) {
        guard !pendingTriages.isEmpty else { return }
        if drafts.isEmpty {
            finishCurrentTriage()
            return
        }
        pendingTriages[0].drafts = drafts
        pendingTriages[0].cursor = min(max(cursor, 0), drafts.count - 1)
        if let deckID {
            pendingTriages[0].deckID = deckID
        }
        persistTriages()
    }

    func finishCurrentTriage() {
        guard !pendingTriages.isEmpty else { return }
        pendingTriages.removeFirst()
        persistTriages()
    }

    private func persistTriages() {
        ShareImportStore.saveTriageBatches(
            pendingTriages.map {
                ShareImportStore.PersistedTriageBatch(
                    id: $0.id,
                    deckID: $0.deckID,
                    drafts: $0.drafts,
                    cursor: $0.cursor
                )
            }
        )
    }

    func removeFinished(_ id: UUID) {
        jobs.removeAll {
            $0.id == id && ($0.status == .succeeded || $0.status == .failed)
        }
    }

    func clearFinished() {
        jobs.removeAll { $0.status == .succeeded || $0.status == .failed }
    }

    /// Pull Share / Action pending jobs into the in-app generation queue.
    func ingestPendingShareJobsIfNeeded() {
        ShareImportStore.resetStaleProcessingJob()
        guard let job = ShareImportStore.claimPendingGenerationJob() else { return }

        guard let deckID = SharedDeckStore.pendingTargetDeckID
            ?? SharedDeckStore.lastSelectedDeckID
            ?? SharedDeckStore.resolvedSelectedDeckID() else {
            ShareImportStore.clearGenerationJob()
            ToastCenter.shared.show(L10n.deckExtensionEmptyCatalogHint)
            return
        }

        let deckName = SharedDeckStore.loadCatalog()
            .first(where: { $0.id == deckID })?
            .name

        do {
            _ = try enqueue(
                sentence: job.sentence,
                words: job.words,
                deckID: deckID,
                deckName: deckName,
                sourceHint: job.sourceHint,
                sourceImagePath: job.sourceImagePath
            )
            ShareImportStore.clearGenerationJob()
        } catch {
            ShareImportStore.clearGenerationJob()
            ToastCenter.shared.show(error.localizedDescription)
            ShareExtensionNotifier.scheduleNoticeNotification(body: error.localizedDescription)
        }
    }

    private func processNextIfNeeded() {
        guard !isProcessing else { return }
        guard let index = jobs.firstIndex(where: { $0.status == .queued }) else { return }
        isProcessing = true
        jobs[index].status = .running
        let job = jobs[index]

        Task {
            await run(job)
        }
    }

    private func run(_ job: Job) async {
        switch job.kind {
        case .create:
            await runCreate(job)
        case .migrate:
            await runMigration(job)
        }
    }

    private func runCreate(_ job: Job) async {
        do {
            let drafts = try await KimiCardGenerator.generate(
                units: job.units,
                sourceHint: job.sourceHint,
                deckName: job.deckName
            ) { [weak self] completed, total in
                self?.updateProgress(jobID: job.id, completed: completed, total: total)
            } onBatchFinished: { [weak self] sentence, words, drafts, error in
                self?.applyBatch(
                    jobID: job.id,
                    sentence: sentence,
                    words: words,
                    drafts: drafts,
                    error: error
                )
            }

            finishCreateSuccess(jobID: job.id, drafts: drafts)
        } catch {
            finishFailure(jobID: job.id, message: error.localizedDescription)
        }
    }

    private func runMigration(_ job: Job) async {
        guard let context = migrationContext else {
            finishFailure(jobID: job.id, message: L10n.generateEmptyError)
            migrationContext = nil
            return
        }

        var report = job.migrationReport ?? CardContentMigrationReport()
        let batches = job.migrationBatches

        for (index, batch) in batches.enumerated() {
            updateProgress(jobID: job.id, completed: index, total: batches.count)

            do {
                let drafts = try await KimiCardGenerator.generate(
                    sentence: batch.sentence,
                    words: batch.words,
                    sourceHint: batch.sourceHint,
                    deckName: batch.deckName,
                    mode: .full
                )
                let stats = CardContentMigrationService.applyMigrationBatch(
                    drafts: drafts,
                    cardIDs: batch.cardIDs,
                    in: context
                )
                try? context.save()
                report.mergeApplyStats(stats)
                if let jobIndex = jobs.firstIndex(where: { $0.id == job.id }) {
                    jobs[jobIndex].migrationReport = report
                }
                applyMigrationBatch(
                    jobID: job.id,
                    batch: batch,
                    drafts: drafts,
                    error: nil
                )
            } catch {
                let idSet = Set(batch.cardIDs)
                let cards = (try? context.fetch(FetchDescriptor<FlashCard>()))?
                    .filter { idSet.contains($0.id) } ?? []
                report.aiFailures += cards.filter { card in
                    batch.words.contains { $0.caseInsensitiveCompare(card.word) == .orderedSame }
                }.count
                if let jobIndex = jobs.firstIndex(where: { $0.id == job.id }) {
                    jobs[jobIndex].migrationReport = report
                }
                applyMigrationBatch(
                    jobID: job.id,
                    batch: batch,
                    drafts: [],
                    error: error
                )
            }

            updateProgress(jobID: job.id, completed: index + 1, total: batches.count)
        }

        finishMigrationSuccess(jobID: job.id, report: report)
        migrationContext = nil
    }

    private func updateProgress(jobID: UUID, completed: Int, total: Int) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[index].completedBatches = completed
        jobs[index].totalBatches = max(total, jobs[index].totalBatches)
    }

    private func applyBatch(
        jobID: UUID,
        sentence: String,
        words: [String],
        drafts: [GeneratedCardDraft],
        error: Error?
    ) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        let sentenceKey = SharedDedupeIndex.normalizedSentence(sentence)
        let wordKeys = Set(words.map(SharedDedupeIndex.normalizedWord))
        let draftWordKeys = Set(drafts.map { SharedDedupeIndex.normalizedWord($0.word) })

        for i in jobs[index].words.indices {
            let item = jobs[index].words[i]
            guard SharedDedupeIndex.normalizedSentence(item.sentence) == sentenceKey,
                  wordKeys.contains(SharedDedupeIndex.normalizedWord(item.word)) else {
                continue
            }
            if error != nil {
                jobs[index].words[i].status = .failed
            } else if draftWordKeys.contains(SharedDedupeIndex.normalizedWord(item.word)) {
                jobs[index].words[i].status = .done
            } else {
                jobs[index].words[i].status = .failed
            }
        }
        jobs[index].drafts.append(contentsOf: drafts)
    }

    private func applyMigrationBatch(
        jobID: UUID,
        batch: CardContentMigrationBatch,
        drafts: [GeneratedCardDraft],
        error: Error?
    ) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        let sentenceKey = SharedDedupeIndex.normalizedSentence(batch.sentence)
        let wordKeys = Set(batch.words.map(SharedDedupeIndex.normalizedWord))
        let draftWordKeys = Set(drafts.map { SharedDedupeIndex.normalizedWord($0.word) })

        for i in jobs[index].words.indices {
            let item = jobs[index].words[i]
            guard SharedDedupeIndex.normalizedSentence(item.sentence) == sentenceKey,
                  wordKeys.contains(SharedDedupeIndex.normalizedWord(item.word)) else {
                continue
            }
            if error != nil {
                jobs[index].words[i].status = .failed
            } else if draftWordKeys.contains(SharedDedupeIndex.normalizedWord(item.word)) {
                jobs[index].words[i].status = .done
            } else {
                jobs[index].words[i].status = .failed
            }
        }
    }

    private func finishCreateSuccess(jobID: UUID, drafts: [GeneratedCardDraft]) {
        defer {
            isProcessing = false
            processNextIfNeeded()
        }
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }

        if drafts.isEmpty {
            jobs[index].status = .failed
            jobs[index].errorMessage = L10n.generateEmptyError
            for i in jobs[index].words.indices where jobs[index].words[i].status == .running
                || jobs[index].words[i].status == .pending {
                jobs[index].words[i].status = .failed
            }
            ToastCenter.shared.show(L10n.generateEmptyError)
            return
        }

        jobs[index].status = .succeeded
        var stamped = drafts
        if let path = jobs[index].sourceImagePath {
            for i in stamped.indices {
                stamped[i].sourceImagePath = path
            }
        }
        jobs[index].drafts = stamped
        jobs[index].completedBatches = jobs[index].totalBatches
        for i in jobs[index].words.indices where jobs[index].words[i].status == .running
            || jobs[index].words[i].status == .pending {
            let wordKey = SharedDedupeIndex.normalizedWord(jobs[index].words[i].word)
            let hasDraft = stamped.contains {
                SharedDedupeIndex.normalizedWord($0.word) == wordKey
            }
            jobs[index].words[i].status = hasDraft ? .done : .failed
        }

        let skipped = jobs[index].skippedDuplicates
        enqueueTriage(
            drafts: stamped,
            deckID: jobs[index].deckID,
            skippedDuplicates: skipped
        )
        if skipped > 0 {
            ToastCenter.shared.show(L10n.createGenerateSuccessSkipped(stamped.count, skipped))
        } else {
            ToastCenter.shared.show(L10n.createGenerateSuccess(stamped.count))
        }
    }

    private func finishMigrationSuccess(jobID: UUID, report: CardContentMigrationReport) {
        defer {
            isProcessing = false
            processNextIfNeeded()
        }
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }

        jobs[index].status = .succeeded
        jobs[index].completedBatches = jobs[index].totalBatches
        jobs[index].migrationReport = report
        for i in jobs[index].words.indices where jobs[index].words[i].status == .running
            || jobs[index].words[i].status == .pending {
            jobs[index].words[i].status = .done
        }

        if report.contentRefreshed > 0
            || report.frontsUpdated > 0
            || report.backsSplit > 0
            || report.phoneticsFilled > 0
            || report.sourcesFilled > 0 {
            DeckCardCountService.notifyDataMaintenance()
        }

        ToastCenter.shared.show(report.summaryMessage)
    }

    private func finishFailure(jobID: UUID, message: String) {
        defer {
            isProcessing = false
            if let job = jobs.first(where: { $0.id == jobID }), job.kind == .migrate {
                migrationContext = nil
            }
            processNextIfNeeded()
        }
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[index].status = .failed
        jobs[index].errorMessage = message
        for i in jobs[index].words.indices where jobs[index].words[i].status == .running
            || jobs[index].words[i].status == .pending {
            jobs[index].words[i].status = .failed
        }
        AppLog.error("Card generation failed: \(message)", category: "Create")
        ToastCenter.shared.show(message)
    }
}

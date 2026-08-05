import Foundation
import SwiftUI

@MainActor
final class CardGenerationQueue: ObservableObject {
    static let shared = CardGenerationQueue()

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

        var progressFraction: Double {
            guard totalBatches > 0 else { return status == .succeeded ? 1 : 0 }
            return Double(completedBatches) / Double(totalBatches)
        }

        var isActive: Bool {
            status == .queued || status == .running
        }
    }

    struct ReadyPreview: Equatable {
        let jobID: UUID
        let drafts: [GeneratedCardDraft]
        let deckID: UUID
        let skippedDuplicates: Int
    }

    @Published private(set) var jobs: [Job] = []
    @Published var readyPreview: ReadyPreview?

    private var isProcessing = false

    var activeJobs: [Job] {
        jobs.filter(\.isActive)
    }

    var hasActiveJobs: Bool {
        !activeJobs.isEmpty
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
            errorMessage: nil
        )
        jobs.insert(job, at: 0)
        processNextIfNeeded()
        return job.id
    }

    func dismissReadyPreview() {
        readyPreview = nil
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

            finishSuccess(jobID: job.id, drafts: drafts)
        } catch {
            finishFailure(jobID: job.id, message: error.localizedDescription)
        }
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

    private func finishSuccess(jobID: UUID, drafts: [GeneratedCardDraft]) {
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
        readyPreview = ReadyPreview(
            jobID: jobID,
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

    private func finishFailure(jobID: UUID, message: String) {
        defer {
            isProcessing = false
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

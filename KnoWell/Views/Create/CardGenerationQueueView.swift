import SwiftUI

struct CardGenerationQueueView: View {
    @ObservedObject var queue: CardGenerationQueue
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if queue.jobs.isEmpty {
                    ContentUnavailableView(
                        L10n.createQueueEmptyTitle,
                        systemImage: "tray",
                        description: Text(L10n.createQueueEmptyBody)
                    )
                } else {
                    List {
                        ForEach(queue.jobs) { job in
                            Section {
                                ForEach(job.words) { item in
                                    wordRow(item)
                                }
                            } header: {
                                jobHeader(job)
                            } footer: {
                                jobFooter(job)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(L10n.createQueueTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.done) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if queue.jobs.contains(where: { !$0.isActive }) {
                        Button(L10n.createQueueClearFinished) {
                            queue.clearFinished()
                        }
                    }
                }
            }
        }
    }

    private func jobHeader(_ job: CardGenerationQueue.Job) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(statusTitle(job.status))
                    .font(.caption.weight(.semibold))
                Spacer()
                if job.totalBatches > 0, job.isActive {
                    Text("\(job.completedBatches)/\(job.totalBatches)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Text(job.sentencePreview)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if job.isActive, job.totalBatches > 0 {
                ProgressView(value: job.progressFraction)
                    .tint(AppColor.accent)
            }
        }
        .textCase(nil)
        .padding(.vertical, 4)
    }

    private func jobFooter(_ job: CardGenerationQueue.Job) -> some View {
        Group {
            if let error = job.errorMessage {
                Text(error)
            } else if job.skippedDuplicates > 0 {
                Text(L10n.createQueueSkipped(job.skippedDuplicates))
            }
        }
    }

    private func wordRow(_ item: CardGenerationQueue.WordItem) -> some View {
        HStack(spacing: 10) {
            statusIcon(item.status)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.word)
                    .font(.body.weight(.medium))
                Text(item.sentence)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Text(wordStatusTitle(item.status))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func statusIcon(_ status: CardGenerationQueue.WordStatus) -> some View {
        Group {
            switch status {
            case .pending:
                Image(systemName: "circle")
                    .foregroundStyle(.tertiary)
            case .running:
                ProgressView()
                    .controlSize(.small)
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            case .skipped:
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 22)
    }

    private func statusTitle(_ status: CardGenerationQueue.JobStatus) -> String {
        switch status {
        case .queued: L10n.createQueueStatusQueued
        case .running: L10n.createQueueStatusRunning
        case .succeeded: L10n.createQueueStatusSucceeded
        case .failed: L10n.createQueueStatusFailed
        }
    }

    private func wordStatusTitle(_ status: CardGenerationQueue.WordStatus) -> String {
        switch status {
        case .pending: L10n.createQueueWordPending
        case .running: L10n.createQueueWordRunning
        case .done: L10n.createQueueWordDone
        case .failed: L10n.createQueueWordFailed
        case .skipped: L10n.createQueueWordSkipped
        }
    }
}

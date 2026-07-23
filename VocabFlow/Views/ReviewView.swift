import SwiftUI
import SwiftData

struct ReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ReviewSettingsStore.self) private var reviewSettings

    @State private var plan: ReviewQueuePlan?
    @State private var hasAnyCards = false
    @State private var isLoading = true
    @State private var showQuotaDetail = false

    private var refreshToken: Int {
        reviewSettings.revision
    }

    private var sessionSignature: String {
        guard let plan else { return "loading" }
        let sessionCards = plan.sessionCards
        let head = sessionCards.prefix(3).map(\.id.uuidString).joined(separator: ",")
        return "\(reviewSettings.revision)-\(sessionCards.count)-\(head)"
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView(L10n.deckLoading)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let plan {
                    if plan.sessionCards.isEmpty {
                        emptyState(plan: plan)
                    } else {
                        VStack(spacing: 0) {
                            ReviewQuotaBanner(plan: plan) {
                                showQuotaDetail = true
                            }
                            CardReviewSessionView(cards: plan.sessionCards)
                                .id(sessionSignature)
                        }
                    }
                }
            }
            .navigationTitle(L10n.reviewTitle)
            .sheet(isPresented: $showQuotaDetail) {
                if let plan {
                    ReviewQuotaDetailSheet(plan: plan)
                }
            }
        }
        .task(id: refreshToken) {
            await loadPlan()
        }
        .onReceive(NotificationCenter.default.publisher(for: .reviewQueueDidChange)) { _ in
            Task { await loadPlan() }
        }
    }

    @ViewBuilder
    private func emptyState(plan: ReviewQueuePlan) -> some View {
        if !hasAnyCards {
            ContentUnavailableView {
                Label(L10n.reviewEmptyTitle, systemImage: "tray")
            } description: {
                Text(L10n.reviewEmptyNoCards)
            }
        } else if plan.hasDeferredCards {
            ContentUnavailableView {
                Label(L10n.reviewQuotaReachedTitle, systemImage: "clock")
            } description: {
                Text(L10n.reviewQuotaReachedMessage(plan.deferredTotalCount))
            } actions: {
                Button(L10n.reviewQuotaDetailTitle) {
                    showQuotaDetail = true
                }
            }
        } else {
            ContentUnavailableView {
                Label(L10n.reviewEmptyTitle, systemImage: "checkmark.circle")
            } description: {
                Text(L10n.reviewEmptyDone)
            }
        }
    }

    @MainActor
    private func loadPlan() async {
        if plan == nil {
            isLoading = true
        }

        await Task.yield()

        var emptyDescriptor = FetchDescriptor<FlashCard>()
        emptyDescriptor.fetchLimit = 1
        hasAnyCards = !((try? modelContext.fetch(emptyDescriptor)) ?? []).isEmpty

        let dueDate = Date.now
        let descriptor = FetchDescriptor<FlashCard>(
            predicate: #Predicate<FlashCard> { card in
                card.nextReviewDate <= dueDate
            },
            sortBy: [SortDescriptor(\FlashCard.nextReviewDate)]
        )
        guard let cards = try? modelContext.fetch(descriptor) else {
            isLoading = false
            return
        }

        plan = ReviewQueueBuilder.plan(
            from: cards,
            dailyNewLimit: reviewSettings.dailyNewLimit,
            dailyReviewLimit: reviewSettings.dailyReviewLimit
        )
        isLoading = false
    }
}

private struct ReviewQuotaBanner: View {
    let plan: ReviewQueuePlan
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                quotaItem(
                    title: L10n.reviewQuotaNew,
                    studied: plan.newStudiedToday,
                    limit: plan.newLimit
                )
                quotaItem(
                    title: L10n.reviewQuotaReview,
                    studied: plan.reviewStudiedToday,
                    limit: plan.reviewLimit
                )
                Spacer(minLength: 0)
                Image(systemName: "info.circle")
                    .font(.caption)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .buttonStyle(.plain)
    }

    private func quotaItem(title: String, studied: Int, limit: Int) -> some View {
        Text(L10n.reviewQuotaProgress(title, studied: studied, limit: limit))
    }
}

private struct ReviewQuotaDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let plan: ReviewQueuePlan

    var body: some View {
        NavigationStack {
            List {
                Section(L10n.reviewQuotaDetailToday) {
                    quotaRow(
                        title: L10n.reviewQuotaNew,
                        studied: plan.newStudiedToday,
                        limit: plan.newLimit,
                        deferred: plan.deferredNewCount
                    )
                    quotaRow(
                        title: L10n.reviewQuotaReview,
                        studied: plan.reviewStudiedToday,
                        limit: plan.reviewLimit,
                        deferred: plan.deferredReviewCount
                    )
                }

                if plan.hasDeferredCards {
                    Section {
                        Text(L10n.reviewQuotaDetailDeferredMessage(plan.deferredTotalCount))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Text(L10n.reviewQuotaDetailHint)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(L10n.reviewQuotaDetailTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.close) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func quotaRow(title: String, studied: Int, limit: Int, deferred: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(L10n.reviewQuotaProgress(title, studied: studied, limit: limit))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if deferred > 0 {
                Text(L10n.reviewQuotaDetailDeferred(deferred))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    ReviewView()
        .environment(ReviewSettingsStore.shared)
        .modelContainer(for: FlashCard.self, inMemory: true)
}

import SwiftUI
import SwiftData

struct ReviewView: View {
    @Query(sort: \FlashCard.nextReviewDate) private var allCards: [FlashCard]

    @State private var showQuotaDetail = false

    private var plan: ReviewQueuePlan {
        ReviewQueueBuilder.plan(from: allCards)
    }

    var body: some View {
        NavigationStack {
            Group {
                if plan.sessionCards.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        ReviewQuotaBanner(plan: plan) {
                            showQuotaDetail = true
                        }
                        CardReviewSessionView(cards: plan.sessionCards)
                    }
                }
            }
            .navigationTitle(L10n.reviewTitle)
            .sheet(isPresented: $showQuotaDetail) {
                ReviewQuotaDetailSheet(plan: plan)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if allCards.isEmpty {
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
        .modelContainer(for: FlashCard.self, inMemory: true)
}

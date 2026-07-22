import SwiftUI
import SwiftData

struct ReviewView: View {
    @Query(sort: \FlashCard.nextReviewDate) private var allCards: [FlashCard]

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
                        ReviewQuotaBanner(plan: plan)
                        CardReviewSessionView(cards: plan.sessionCards)
                    }
                }
            }
            .navigationTitle(L10n.reviewTitle)
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

    var body: some View {
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
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func quotaItem(title: String, studied: Int, limit: Int) -> some View {
        Text(L10n.reviewQuotaProgress(title, studied: studied, limit: limit))
    }
}

#Preview {
    ReviewView()
        .modelContainer(for: FlashCard.self, inMemory: true)
}

import SwiftUI
import SwiftData

struct ReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ReviewSettingsStore.self) private var reviewSettings

    @Query(sort: [SortDescriptor(\Deck.sortOrder), SortDescriptor(\Deck.createdAt)])
    private var decks: [Deck]

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
                            CardReviewSessionView(
                                cards: plan.sessionCards,
                                showDeckName: reviewSettings.reviewDeckID == nil
                            )
                                .id(sessionSignature)
                        }
                    }
                }
            }
            .appPageBackground()
            .appNavTitle(L10n.reviewTitle)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    reviewDeckMenu
                }
            }
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

    private var reviewDeckMenu: some View {
        Menu {
            Button {
                reviewSettings.setReviewDeckID(nil)
            } label: {
                if reviewSettings.reviewDeckID == nil {
                    Label(L10n.reviewDeckFilterAll, systemImage: "checkmark")
                } else {
                    Text(L10n.reviewDeckFilterAll)
                }
            }

            ForEach(decks) { deck in
                Button {
                    reviewSettings.setReviewDeckID(deck.id)
                } label: {
                    if reviewSettings.reviewDeckID == deck.id {
                        Label(deck.name, systemImage: "checkmark")
                    } else {
                        Text(deck.name)
                    }
                }
            }
        } label: {
            Label(reviewDeckMenuTitle, systemImage: "books.vertical")
        }
    }

    private var reviewDeckMenuTitle: String {
        if let deckID = reviewSettings.reviewDeckID,
           let deck = decks.first(where: { $0.id == deckID }) {
            return deck.name
        }
        return L10n.reviewDeckFilterAll
    }

    @ViewBuilder
    private func emptyState(plan: ReviewQueuePlan) -> some View {
        if !hasAnyCards {
            AppEmptyState(
                title: L10n.reviewEmptyTitle,
                message: L10n.reviewEmptyGoCreate,
                systemImage: "sparkles.rectangle.stack"
            )
        } else if plan.hasDeferredCards {
            AppEmptyState(
                title: L10n.reviewQuotaReachedTitle,
                message: L10n.reviewQuotaReachedMessage(plan.deferredTotalCount),
                systemImage: "clock",
                actionTitle: L10n.reviewQuotaDetailTitle,
                action: { showQuotaDetail = true }
            )
        } else {
            AppEmptyState(
                title: L10n.reviewEmptyTitle,
                message: L10n.reviewEmptyDone,
                systemImage: "checkmark.circle"
            )
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
        guard let allCards = try? modelContext.fetch(descriptor) else {
            isLoading = false
            return
        }

        let cards = ReviewQueueBuilder.cards(in: reviewSettings.reviewDeckID, from: allCards)

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
            HStack(spacing: AppSpacing.md) {
                quotaBar(
                    studied: plan.newStudiedToday,
                    limit: plan.newLimit,
                    label: L10n.reviewQuotaNew
                )
                quotaBar(
                    studied: plan.reviewStudiedToday,
                    limit: plan.reviewLimit,
                    label: L10n.reviewQuotaReview
                )
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.reviewQuotaDetailTitle)
    }

    private func quotaBar(studied: Int, limit: Int, label: String) -> some View {
        let progress: Double = {
            guard limit > 0 else { return 0 }
            return min(1, Double(studied) / Double(limit))
        }()

        return VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: progress)
                .tint(AppColor.accent)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.reviewQuotaProgress(label, studied: studied, limit: limit))
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
                            .font(AppFont.secondary())
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Text(L10n.reviewQuotaDetailHint)
                        .font(AppFont.secondary())
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
                .font(AppFont.sectionTitle())
            Text(L10n.reviewQuotaProgress(title, studied: studied, limit: limit))
                .font(AppFont.secondary())
                .foregroundStyle(.secondary)
            if deferred > 0 {
                Text(L10n.reviewQuotaDetailDeferred(deferred))
                    .font(AppFont.caption())
                    .foregroundStyle(AppColor.warning)
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

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
    @State private var isSessionActive = false

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
                        .tint(AppColor.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let plan {
                    if isSessionActive, !plan.sessionCards.isEmpty {
                        sessionContent(plan: plan)
                    } else {
                        ReviewHomeView(
                            plan: plan,
                            hasAnyCards: hasAnyCards,
                            decks: decks,
                            activeDeckID: reviewSettings.reviewDeckID ?? DeckSettings.lastSelectedDeckID,
                            onStartReview: { isSessionActive = true },
                            onShowQuota: { showQuotaDetail = true },
                            onSelectDeck: { deckID in
                                reviewSettings.setReviewDeckID(deckID)
                            }
                        )
                    }
                }
            }
            .appPageBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if isSessionActive {
                        reviewDeckMenu
                    } else {
                        BrandMark()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSessionActive {
                        Button(L10n.reviewSessionDone) {
                            finishSession()
                        }
                    } else {
                        HStack(spacing: 14) {
                            reviewDeckMenu
                            Button {
                                AppTab.requestSettings()
                            } label: {
                                AppIcon.symbol("gearshape")
                            }
                            .accessibilityLabel(L10n.settingsTitle)
                        }
                    }
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

    @ViewBuilder
    private func sessionContent(plan: ReviewQueuePlan) -> some View {
        CardReviewSessionView(
            cards: plan.sessionCards,
            showDeckName: reviewSettings.reviewDeckID == nil,
            onSessionComplete: { finishSession() }
        )
        .id(sessionSignature)
    }

    private func finishSession() {
        isSessionActive = false
        Task { await loadPlan() }
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

        if isSessionActive, plan?.sessionCards.isEmpty == true {
            isSessionActive = false
        }
    }
}

// MARK: - Review Home

private struct ReviewHomeView: View {
    let plan: ReviewQueuePlan
    let hasAnyCards: Bool
    let decks: [Deck]
    let activeDeckID: UUID?
    let onStartReview: () -> Void
    let onShowQuota: () -> Void
    let onSelectDeck: (UUID?) -> Void

    private var dueCount: Int { plan.sessionCards.count }

    private var newQuotaDisplay: String {
        plan.newLimit == 0 ? "∞" : "\(plan.newLimit)"
    }

    private var recentDecks: [Deck] {
        Array(decks.prefix(3))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                statsCard

                if !hasAnyCards {
                    emptyCTA
                } else if dueCount > 0 {
                    Button(action: onStartReview) {
                        Text(L10n.reviewHomeStart)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle(prominent: true))
                } else {
                    doneCTA
                }

                quickCaptureRow

                if !recentDecks.isEmpty {
                    recentDecksSection
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.top, AppSpacing.md)
            .padding(.bottom, AppSpacing.lg)
        }
    }

    private var statsCard: some View {
        AppSurfaceCard {
            VStack(spacing: AppSpacing.md) {
                HStack(spacing: 0) {
                    statColumn(value: "\(dueCount)", label: L10n.homeStatDue)
                    Divider().frame(height: 36)
                    statColumn(value: newQuotaDisplay, label: L10n.homeStatNewQuota)
                    Divider().frame(height: 36)
                    statColumn(
                        value: L10n.homeStatStreakValue(StudyStreakStore.currentStreak),
                        label: L10n.homeStatStreak
                    )
                }

                if plan.hasDeferredCards {
                    Button(action: onShowQuota) {
                        Text(L10n.reviewQuotaReachedMessage(plan.deferredTotalCount))
                            .font(AppFont.weak())
                            .foregroundStyle(AppColor.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func statColumn(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(AppFont.statValue())
                .foregroundStyle(AppColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(AppFont.weak())
                .foregroundStyle(AppColor.textTertiary.opacity(0.72))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyCTA: some View {
        Button {
            AppTab.request(.create)
        } label: {
            Text(L10n.reviewEmptyGoCreate)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryButtonStyle(prominent: true))
    }

    private var doneCTA: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(L10n.reviewHomeDoneToday)
                .font(AppFont.secondary())
                .foregroundStyle(AppColor.textSecondary)

            Button {
                AppTab.request(.create)
            } label: {
                Text(L10n.reviewEmptyGoCreate)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    private var quickCaptureRow: some View {
        HStack(spacing: AppSpacing.sm) {
            CompactIconAction(systemImage: "camera", title: nil) {
                AppTab.request(.create)
            }
            .accessibilityLabel(L10n.importFromCamera)

            CompactIconAction(systemImage: "photo", title: nil) {
                AppTab.request(.create)
            }
            .accessibilityLabel(L10n.importFromPhoto)

            CompactIconAction(systemImage: "doc.on.clipboard", title: nil) {
                AppTab.request(.create)
            }
            .accessibilityLabel(L10n.createQuickPaste)
        }
    }

    private var recentDecksSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(L10n.homeRecentDecks)
                .font(AppFont.weak())
                .foregroundStyle(AppColor.textTertiary)

            VStack(spacing: 0) {
                ForEach(Array(recentDecks.enumerated()), id: \.element.id) { index, deck in
                    Button {
                        onSelectDeck(deck.id)
                        AppTab.request(.library)
                    } label: {
                        HStack {
                            Text(deck.name)
                                .font(AppFont.body())
                                .foregroundStyle(AppColor.textBody)
                            Spacer()
                            Text("\(deck.cardCount)")
                                .font(AppFont.caption())
                                .foregroundStyle(AppColor.textTertiary)
                        }
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)

                    if index < recentDecks.count - 1 {
                        Divider().opacity(0.6)
                    }
                }
            }
        }
    }
}

private struct ReviewQuotaDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let plan: ReviewQueuePlan

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.md) {
                    AppSurfaceCard {
                        VStack(alignment: .leading, spacing: AppSpacing.md) {
                            Text(L10n.reviewQuotaDetailToday)
                                .font(AppFont.caption())
                                .foregroundStyle(AppColor.textSecondary)

                            quotaRow(
                                title: L10n.reviewQuotaNew,
                                studied: plan.newStudiedToday,
                                limit: plan.newLimit,
                                deferred: plan.deferredNewCount
                            )

                            Divider()

                            quotaRow(
                                title: L10n.reviewQuotaReview,
                                studied: plan.reviewStudiedToday,
                                limit: plan.reviewLimit,
                                deferred: plan.deferredReviewCount
                            )
                        }
                    }

                    if plan.hasDeferredCards {
                        AppSurfaceCard {
                            Text(L10n.reviewQuotaDetailDeferredMessage(plan.deferredTotalCount))
                                .font(AppFont.secondary())
                                .foregroundStyle(AppColor.textSecondary)
                        }
                    }

                    AppSurfaceCard {
                        Text(L10n.reviewQuotaDetailHint)
                            .font(AppFont.secondary())
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
                .padding(AppSpacing.md)
            }
            .appPageBackground()
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
                .foregroundStyle(AppColor.textPrimary)
            Text(L10n.reviewQuotaProgress(title, studied: studied, limit: limit))
                .font(AppFont.secondary())
                .foregroundStyle(AppColor.textSecondary)
            if deferred > 0 {
                Text(L10n.reviewQuotaDetailDeferred(deferred))
                    .font(AppFont.caption())
                    .foregroundStyle(AppColor.warning)
            }
        }
    }
}

#Preview {
    ReviewView()
        .environment(ReviewSettingsStore.shared)
        .modelContainer(for: FlashCard.self, inMemory: true)
}

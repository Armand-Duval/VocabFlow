import SwiftUI
import SwiftData

struct ReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ReviewSettingsStore.self) private var reviewSettings
    @EnvironmentObject private var shareImport: ShareImportCoordinator

    @State private var plan: ReviewQueuePlan?
    @State private var hasAnyCards = false
    @State private var isLoading = true
    @State private var showQuotaDetail = false
    @State private var isSessionActive = false
    @State private var dailyReflection: DailyReflection?

    private var activeDeckID: UUID? {
        DeckSettings.lastSelectedDeckID
    }

    private var refreshToken: String {
        "\(reviewSettings.revision)|\(activeDeckID?.uuidString ?? "all")"
    }

    private var sessionSignature: String {
        guard let plan else { return "loading" }
        let sessionCards = plan.sessionCards
        let head = sessionCards.prefix(3).map(\.id.uuidString).joined(separator: ",")
        return "\(refreshToken)-\(sessionCards.count)-\(head)"
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
                            dailyReflection: dailyReflection,
                            onStartReview: { isSessionActive = true },
                            onShowQuota: { showQuotaDetail = true },
                            onCollectReflection: { reflection in
                                shareImport.importPayload(
                                    ShareImportPayload(
                                        sentence: reflection.sentence,
                                        source: .clipboard
                                    )
                                )
                                AppTab.request(.create)
                            }
                        )
                    }
                }
            }
            .appPageBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(isSessionActive ? .hidden : .automatic, for: .navigationBar)
            .toolbar {
                if !isSessionActive {
                    ToolbarItem(placement: .topBarLeading) {
                        BrandMark()
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            AppTab.requestSettings()
                        } label: {
                            AppIcon.symbol("gearshape")
                        }
                        .accessibilityLabel(L10n.settingsTitle)
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
        .onReceive(NotificationCenter.default.publisher(for: .activeDeckDidChange)) { _ in
            Task { await loadPlan() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .libraryCatalogDidChange)) { _ in
            Task { await loadPlan() }
        }
    }

    @ViewBuilder
    private func sessionContent(plan: ReviewQueuePlan) -> some View {
        CardReviewSessionView(
            cards: plan.sessionCards,
            showDeckName: activeDeckID == nil,
            onSessionComplete: { finishSession() }
        )
        .id(sessionSignature)
    }

    private func finishSession() {
        isSessionActive = false
        Task { await loadPlan() }
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

        let cards = ReviewQueueBuilder.cards(in: activeDeckID, from: allCards)

        plan = ReviewQueueBuilder.plan(
            from: cards,
            dailyNewLimit: reviewSettings.dailyNewLimit,
            dailyReviewLimit: reviewSettings.dailyReviewLimit
        )

        // Instant curated/cache first; AI timely line refreshes in background (once/day).
        dailyReflection = DailyReflectionService.cachedOrCurated()
        isLoading = false

        if isSessionActive, plan?.sessionCards.isEmpty == true {
            isSessionActive = false
        }

        Task {
            let previous = dailyReflection
            let refreshed = await DailyReflectionService.refreshIfNeeded()
            await MainActor.run {
                // Avoid flashing a foreign curated line then replacing with Chinese-only AI.
                if refreshed != previous {
                    dailyReflection = refreshed
                }
            }
        }
    }
}

// MARK: - Review Home

private struct ReviewHomeView: View {
    let plan: ReviewQueuePlan
    let hasAnyCards: Bool
    let dailyReflection: DailyReflection?
    let onStartReview: () -> Void
    let onShowQuota: () -> Void
    let onCollectReflection: (DailyReflection) -> Void

    private var dueCount: Int { plan.sessionCards.count }

    private var newQuotaDisplay: String {
        plan.newLimit == 0 ? "∞" : "\(plan.newLimit)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                AppSurfaceCard(padding: AppSpacing.md) {
                    dueZone
                }

                if let dailyReflection {
                    AppSurfaceCard(padding: AppSpacing.md) {
                        literaryReflection(dailyReflection)
                    }
                } else if dueCount == 0, hasAnyCards {
                    AppSurfaceCard(padding: AppSpacing.md) {
                        Text(L10n.reviewHomeDoneHint)
                            .font(AppFont.secondary())
                            .foregroundStyle(AppColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.top, AppSpacing.md)
            .padding(.bottom, AppSpacing.lg)
        }
    }

    private var dueZone: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            if !hasAnyCards {
                statusHeader(compact: true)
                emptyCTA
            } else if dueCount == 0 {
                statusHeader(compact: true)
                doneStatusBlock
            } else {
                statusHeader(compact: false)
                if let tip = activityTipText {
                    homeTip(tip)
                }
                if plan.hasDeferredCards {
                    Button(action: onShowQuota) {
                        Text(L10n.reviewQuotaReachedMessage(plan.deferredTotalCount))
                            .font(AppFont.helper())
                            .foregroundStyle(AppColor.textMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
                Button(action: onStartReview) {
                    Text(L10n.reviewHomeStart)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(prominent: true))
            }
        }
    }

    /// Number + one meta line (+ optional deferred). Keeps grey noise out of the status story.
    private func statusHeader(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if compact {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                    Text("0")
                        .font(AppFont.heroValueCompact())
                        .foregroundStyle(AppColor.textPrimary)
                    Text(L10n.homeStatDue)
                        .font(AppFont.caption())
                        .foregroundStyle(AppColor.textTertiary)
                    Spacer(minLength: 0)
                }
            } else {
                Text(L10n.homeStatDue)
                    .font(AppFont.caption())
                    .foregroundStyle(AppColor.textTertiary)

                Text("\(dueCount)")
                    .font(AppFont.heroValue())
                    .foregroundStyle(AppColor.textPrimary)
                    .contentTransition(.numericText())
            }

            Text(metaLine)
                .font(AppFont.helper())
                .foregroundStyle(AppColor.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Done-for-today: closing line leads; tip / deferred stay as footnotes.
    private var doneStatusBlock: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(L10n.reviewHomeDoneToday)
                .font(AppFont.secondary())
                .foregroundStyle(AppColor.textSecondary)

            if let tip = activityTipText {
                homeTip(tip)
            }

            if plan.hasDeferredCards {
                Button(action: onShowQuota) {
                    Text(L10n.reviewQuotaReachedMessage(plan.deferredTotalCount))
                        .font(AppFont.helper())
                        .foregroundStyle(AppColor.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func homeTip(_ tip: String) -> some View {
        Text(tip)
            .font(AppFont.helper())
            .foregroundStyle(AppColor.textMuted)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(tip)
    }

    private var activityTipText: String? {
        guard hasAnyCards,
              let summary = StudyActivityStore.recentSummary(),
              summary.uniqueWords > 0 || summary.uniqueSentences > 0 else {
            return nil
        }
        if summary.spanDays <= 1 {
            return L10n.reviewHomeActivityToday(summary.uniqueWords, summary.uniqueSentences)
        }
        return L10n.reviewHomeActivityRecent(
            summary.spanDays,
            summary.uniqueWords,
            summary.uniqueSentences
        )
    }

    private var metaLine: String {
        let streak = L10n.homeStatStreakValue(StudyStreakStore.currentStreak)
        return "\(L10n.homeStatNewQuota) \(newQuotaDisplay) · \(L10n.homeStatStreak) \(streak)"
    }

    private var emptyCTA: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            if let tip = activityTipText {
                homeTip(tip)
            }

            Text(L10n.reviewEmptyAssistant)
                .font(AppFont.secondary())
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                AppTab.request(.create)
            } label: {
                Text(L10n.reviewEmptyStartCreate)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle(prominent: true))
        }
    }

    private func literaryReflection(_ reflection: DailyReflection) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: 6) {
                Text(L10n.reviewDailyTitle)
                    .font(AppFont.helper())
                    .foregroundStyle(AppColor.textMuted)
                if let occasion = reflection.occasion?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !occasion.isEmpty {
                    Text("·")
                        .font(AppFont.helper())
                        .foregroundStyle(AppColor.textMuted.opacity(0.55))
                    Text(occasion)
                        .font(AppFont.helper())
                        .foregroundStyle(AppColor.textMuted)
                        .lineLimit(1)
                }
            }

            Text(reflection.sentence)
                .font(AppFont.literaryQuote())
                .foregroundStyle(AppColor.textPrimary)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(.top, 2)

            if let translation = reflection.translation?.trimmingCharacters(in: .whitespacesAndNewlines),
               !translation.isEmpty {
                Text(translation)
                    .font(AppFont.secondary())
                    .foregroundStyle(AppColor.textSecondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            if let source = reflection.source?.trimmingCharacters(in: .whitespacesAndNewlines),
               !source.isEmpty {
                Text("—— \(source)")
                    .font(AppFont.helper())
                    .foregroundStyle(AppColor.textMuted)
            }

            TextLinkAction(title: L10n.reviewDailyCollect) {
                onCollectReflection(reflection)
            }
            .padding(.top, 2)
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

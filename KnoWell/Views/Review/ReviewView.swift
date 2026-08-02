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
            let refreshed = await DailyReflectionService.refreshIfNeeded()
            await MainActor.run {
                dailyReflection = refreshed
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
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                if dueCount == 0, hasAnyCards {
                    // Done: quiet stats + literary line as the page focus.
                    compactHeroStats
                    doneCTA
                } else {
                    heroStats

                    if !hasAnyCards {
                        emptyCTA
                    } else {
                        Button(action: onStartReview) {
                            Text(L10n.reviewHomeStart)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle(prominent: true))
                    }

                    quietCaptureRow

                    // Keep「今日一句」visible even when there are cards due.
                    if let dailyReflection {
                        literaryReflection(dailyReflection)
                    }
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.top, AppSpacing.lg)
            .padding(.bottom, AppSpacing.lg)
        }
    }

    private var compactHeroStats: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                Text("0")
                    .font(AppFont.heroValueCompact())
                    .foregroundStyle(AppColor.textPrimary)
                Text(L10n.homeStatDue)
                    .font(AppFont.caption())
                    .foregroundStyle(AppColor.textTertiary)
                Spacer(minLength: 0)
            }

            Text(metaLine)
                .font(AppFont.weak())
                .foregroundStyle(AppColor.textTertiary)

            if plan.hasDeferredCards {
                Button(action: onShowQuota) {
                    Text(L10n.reviewQuotaReachedMessage(plan.deferredTotalCount))
                        .font(AppFont.weak())
                        .foregroundStyle(AppColor.textTertiary.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var heroStats: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(L10n.homeStatDue)
                .font(AppFont.caption())
                .foregroundStyle(AppColor.textTertiary)

            Text("\(dueCount)")
                .font(AppFont.heroValue())
                .foregroundStyle(AppColor.textPrimary)
                .contentTransition(.numericText())

            Text(metaLine)
                .font(AppFont.caption())
                .foregroundStyle(AppColor.textTertiary)

            if plan.hasDeferredCards {
                Button(action: onShowQuota) {
                    Text(L10n.reviewQuotaReachedMessage(plan.deferredTotalCount))
                        .font(AppFont.weak())
                        .foregroundStyle(AppColor.textTertiary.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metaLine: String {
        let streak = L10n.homeStatStreakValue(StudyStreakStore.currentStreak)
        return "\(L10n.homeStatNewQuota) \(newQuotaDisplay) · \(L10n.homeStatStreak) \(streak)"
    }

    private var emptyCTA: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
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

    /// Done-for-today: the daily line is the companion, not a form card stack.
    private var doneCTA: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text(L10n.reviewHomeDoneToday)
                .font(AppFont.caption())
                .foregroundStyle(AppColor.textTertiary)

            if let dailyReflection {
                literaryReflection(dailyReflection)
            } else {
                Text(L10n.reviewHomeDoneHint)
                    .font(AppFont.secondary())
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func literaryReflection(_ reflection: DailyReflection) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(spacing: 6) {
                Text(L10n.reviewDailyTitle)
                    .font(AppFont.weak())
                    .foregroundStyle(AppColor.textTertiary)
                if let occasion = reflection.occasion?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !occasion.isEmpty {
                    Text("·")
                        .font(AppFont.weak())
                        .foregroundStyle(AppColor.textTertiary.opacity(0.5))
                    Text(occasion)
                        .font(AppFont.weak())
                        .foregroundStyle(AppColor.textTertiary)
                        .lineLimit(1)
                }
            }

            Text(reflection.sentence)
                .font(AppFont.literaryQuote())
                .foregroundStyle(AppColor.textPrimary)
                .lineSpacing(8)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            if let source = reflection.source?.trimmingCharacters(in: .whitespacesAndNewlines),
               !source.isEmpty {
                Text("—— \(source)")
                    .font(AppFont.caption())
                    .foregroundStyle(AppColor.textTertiary)
            }

            TextLinkAction(title: L10n.reviewDailyCollect) {
                onCollectReflection(reflection)
            }
        }
        .padding(.vertical, AppSpacing.sm)
    }

    private var quietCaptureRow: some View {
        HStack(spacing: 6) {
            Text(L10n.createQuickCaptureTitle)
                .font(AppFont.weak())
                .foregroundStyle(AppColor.textTertiary)

            Spacer(minLength: AppSpacing.sm)

            TextLinkAction(title: L10n.createQuickCamera) {
                AppTab.request(.create)
            }

            Text("·")
                .font(AppFont.weak())
                .foregroundStyle(AppColor.textTertiary.opacity(0.45))

            TextLinkAction(title: L10n.createQuickPhoto) {
                AppTab.request(.create)
            }

            Text("·")
                .font(AppFont.weak())
                .foregroundStyle(AppColor.textTertiary.opacity(0.45))

            TextLinkAction(title: L10n.createQuickPaste) {
                AppTab.request(.create)
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

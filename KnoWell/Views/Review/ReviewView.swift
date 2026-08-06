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
    @State private var sessionEpoch = 0
    @State private var dailyReflection: DailyReflection?

    private var activeDeckID: UUID? {
        DeckSettings.lastSelectedDeckID
    }

    private var refreshToken: String {
        "\(reviewSettings.revision)|\(activeDeckID?.uuidString ?? "all")"
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
                            onStartReview: {
                                sessionEpoch &+= 1
                                isSessionActive = true
                            },
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
            // Don't rebuild mid-session — rating / AI regenerate must not reshuffle or remount the queue.
            guard !isSessionActive else { return }
            Task { await loadPlan() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .activeDeckDidChange)) { _ in
            guard !isSessionActive else { return }
            Task { await loadPlan() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .libraryCatalogDidChange)) { _ in
            guard !isSessionActive else { return }
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
        // Stable for the whole session — do not remount when the home plan refreshes.
        .id(sessionEpoch)
    }

    private func finishSession() {
        isSessionActive = false
        Task { await loadPlan() }
    }

    @MainActor
    private func loadPlan() async {
        // Active review owns its queue; rebuilding here would reshuffle and jump away
        // from the card being studied (e.g. after AI regenerate → catalog notify).
        if isSessionActive, plan != nil {
            return
        }

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

    @State private var showReflectionHistory = false

    private var dueCount: Int { plan.sessionCards.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                AppSurfaceCard(padding: AppSpacing.md) {
                    dueZone
                }

                if let dailyReflection {
                    AppSurfaceCard(padding: AppSpacing.sm) {
                        literaryReflection(dailyReflection)
                    }
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.top, AppSpacing.md)
            .padding(.bottom, AppSpacing.lg)
        }
        .sheet(isPresented: $showReflectionHistory) {
            DailyReflectionHistoryView(onCollect: onCollectReflection)
        }
    }

    private var dueZone: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            dueHero

            if hasAnyCards, let metaLine = compactMetaLine {
                Button(action: onShowQuota) {
                    Text(metaLine)
                        .font(AppFont.weak())
                        .foregroundStyle(AppColor.textMuted)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(SoftPressButtonStyle(pressedScale: 0.99, pressedOpacity: 0.9))
                .accessibilityLabel(metaLine)
            }

            if !hasAnyCards {
                emptyCTA
                    .padding(.top, AppSpacing.xs)
            } else if dueCount > 0 {
                // Only show the primary CTA when there is work — avoid a heavy disabled block.
                startReviewButton
                    .padding(.top, AppSpacing.xs)
            }
        }
    }

    /// Level-1: due count is the only hero metric.
    private var dueHero: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
            Text("\(dueCount)")
                .font(AppFont.heroValue())
                .foregroundStyle(AppColor.textPrimary)
                .contentTransition(.numericText())
                .accessibilityLabel(L10n.reviewHomeDueCount(dueCount))

            Text(L10n.homeStatDue)
                .font(AppFont.caption())
                .foregroundStyle(AppColor.textTertiary.opacity(0.85))

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var startReviewButton: some View {
        Button(action: onStartReview) {
            Text(dueCount > 0 ? L10n.reviewHomeStart : L10n.reviewHomeStartDone)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryButtonStyle(prominent: true))
        .disabled(dueCount == 0)
        .accessibilityLabel(dueCount > 0 ? L10n.reviewHomeStart : L10n.reviewHomeStartDone)
    }

    private var studiedToday: Int {
        plan.newStudiedToday + plan.reviewStudiedToday
    }

    /// Quiet habit line only — quota / week live in settings & quota sheet.
    private var compactMetaLine: String? {
        guard hasAnyCards else { return nil }
        return [
            L10n.reviewHomeStudiedToday(studiedToday),
            "\(L10n.homeStatStreak) \(L10n.homeStatStreakValue(StudyStreakStore.currentStreak))"
        ].joined(separator: " · ")
    }

    private var emptyCTA: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
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
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(spacing: 6) {
                Text(L10n.reviewDailyTitle)
                    .font(AppFont.weak())
                    .foregroundStyle(AppColor.textMuted)
                if let occasion = reflection.occasion?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !occasion.isEmpty {
                    Text("·")
                        .font(AppFont.weak())
                        .foregroundStyle(AppColor.textMuted.opacity(0.55))
                    Text(occasion)
                        .font(AppFont.weak())
                        .foregroundStyle(AppColor.textMuted)
                        .lineLimit(1)
                }
            }

            Text(reflection.sentence)
                .font(AppFont.literaryQuote())
                .foregroundStyle(AppColor.textPrimary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            if let translation = reflection.translation?.trimmingCharacters(in: .whitespacesAndNewlines),
               !translation.isEmpty {
                Text(translation)
                    .font(AppFont.helper())
                    .foregroundStyle(AppColor.textSecondary.opacity(0.9))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            if let source = reflection.source?.trimmingCharacters(in: .whitespacesAndNewlines),
               !source.isEmpty {
                Text("—— \(source)")
                    .font(AppFont.weak())
                    .foregroundStyle(AppColor.textMuted)
            }

            HStack(spacing: AppSpacing.md) {
                TextLinkAction(title: L10n.reviewDailyCollect) {
                    onCollectReflection(reflection)
                }
                TextLinkAction(title: L10n.reviewDailyHistoryLink, tone: .muted) {
                    showReflectionHistory = true
                }
                Spacer(minLength: 0)
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

                            Spacer().frame(height: AppSpacing.xs)

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

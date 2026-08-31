import SwiftUI
import SwiftData

struct ReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ReviewSettingsStore.self) private var reviewSettings

    @State private var plan: ReviewQueuePlan?
    @State private var hasAnyCards = false
    @State private var isLoading = true
    @State private var showQuotaDetail = false
    @State private var quotaSheetPlan: ReviewQueuePlan?
    @State private var showReflectionHistory = false
    @State private var showReflectionPreferences = false
    @State private var isSessionActive = false
    @State private var sessionEpoch = 0
    @State private var dailyReflection: DailyReflection?
    @State private var lifetimeStudiedCount = 0
    @State private var isRefreshingReflection = false
    @State private var isCollectingReflection = false
    @State private var todayCapture: CaptureStatsStore.Summary?

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
                            todayCapture: todayCapture,
                            dailyReflection: dailyReflection,
                            isRefreshingReflection: isRefreshingReflection,
                            isCollectingReflection: isCollectingReflection,
                            onStartReview: {
                                sessionEpoch &+= 1
                                isSessionActive = true
                            },
                            onShowQuota: {
                                quotaSheetPlan = plan
                                showQuotaDetail = true
                            },
                            onShowReflectionHistory: { showReflectionHistory = true },
                            onShowReflectionPreferences: { showReflectionPreferences = true },
                            onRefreshReflection: {
                                Task { await refreshDailyReflection(force: true) }
                            },
                            onCollectReflection: { reflection in
                                Task { await collectReflection(reflection) }
                            }
                        )
                    }
                }
            }
            .appPageBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(isSessionActive ? .hidden : .automatic, for: .navigationBar)
            .sheet(isPresented: $showQuotaDetail) {
                ReviewQuotaDetailSheet(
                    plan: quotaSheetPlan ?? plan ?? ReviewQueuePlan(
                        sessionCards: [],
                        newStudiedToday: 0,
                        reviewStudiedToday: 0,
                        newLimit: 0,
                        reviewLimit: 0,
                        deferredNewCount: 0,
                        deferredReviewCount: 0
                    ),
                    lifetimeStudiedCount: lifetimeStudiedCount
                )
            }
            .sheet(isPresented: $showReflectionHistory) {
                DailyReflectionHistoryView(onCollect: { reflection in
                    Task { await collectReflection(reflection) }
                })
            }
            .sheet(isPresented: $showReflectionPreferences) {
                DailyReflectionPreferencesSheet(onSaved: {
                    Task { await refreshDailyReflection(force: true) }
                })
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

        var studiedDescriptor = FetchDescriptor<FlashCard>(
            predicate: #Predicate<FlashCard> { card in
                card.reviewCount > 0
            }
        )
        lifetimeStudiedCount = (try? modelContext.fetchCount(studiedDescriptor)) ?? 0
        todayCapture = CaptureStatsStore.todaySummary(in: modelContext)
        StudyStreakStore.reconcileTotalDays(StudyActivityStore.recordedDayCount())

        let dueDate = Date.now
        let descriptor = FetchDescriptor<FlashCard>(
            predicate: #Predicate<FlashCard> { card in
                card.isSuspended == false && card.nextReviewDate <= dueDate
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

        await refreshDailyReflection(force: false)
    }

    @MainActor
    private func refreshDailyReflection(force: Bool) async {
        if force {
            isRefreshingReflection = true
        }
        defer { if force { isRefreshingReflection = false } }

        let previous = dailyReflection
        let refreshed = force
            ? await DailyReflectionService.refreshNow(replacing: dailyReflection)
            : await DailyReflectionService.refreshIfNeeded()
        if force || refreshed != previous {
            dailyReflection = refreshed
        }
    }

    @MainActor
    private func collectReflection(_ reflection: DailyReflection) async {
        guard !isCollectingReflection else { return }
        isCollectingReflection = true
        defer { isCollectingReflection = false }

        do {
            let draft = try await LiteraryAppreciationGenerator.generate(from: reflection)
            let deck = DeckService.fetchOrCreateDailyReflectionDeck(in: modelContext)
            let result = FlashCardSaver.save(drafts: [draft], to: modelContext, deck: deck)

            if result.skippedAll {
                ToastCenter.shared.show(L10n.reviewDailyCollectDuplicate)
            } else if result.didSaveAny {
                ToastCenter.shared.show(L10n.reviewDailyCollectSuccess)
                NotificationCenter.default.post(name: .reviewQueueDidChange, object: nil)
                await loadPlan()
            }
        } catch {
            ToastCenter.shared.show(error.localizedDescription)
        }
    }
}
// MARK: - Review Home

private struct ReviewHomeView: View {
    let plan: ReviewQueuePlan
    let hasAnyCards: Bool
    let todayCapture: CaptureStatsStore.Summary?
    let dailyReflection: DailyReflection?
    let isRefreshingReflection: Bool
    let isCollectingReflection: Bool
    let onStartReview: () -> Void
    let onShowQuota: () -> Void
    let onShowReflectionHistory: () -> Void
    let onShowReflectionPreferences: () -> Void
    let onRefreshReflection: () -> Void
    let onCollectReflection: (DailyReflection) -> Void

    @State private var appeared = false

    private var dueCount: Int { plan.sessionCards.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                dueComposition
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 8)

                if let dailyReflection {
                    literaryZone(dailyReflection)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 18)
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.top, AppSpacing.sm)
            .padding(.bottom, AppSpacing.xl)
        }
        .appVerticalBounce()
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) {
                appeared = true
            }
        }
    }

    private var dueComposition: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            dueHero

            if hasAnyCards {
                compactStatsLine
            }

            if !hasAnyCards {
                emptyCTA
            } else if dueCount > 0 {
                startReviewButton
            } else {
                Text(L10n.reviewHomeDoneToday)
                    .font(AppFont.secondary())
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
        .appSoftShadow()
    }

    private var compactStatsLine: some View {
        Button(action: onShowQuota) {
            HStack(spacing: AppSpacing.lg) {
                miniStat(value: "\(plan.newStudiedToday)", label: L10n.reviewHomeStatsNew)
                miniStat(value: "\(plan.reviewStudiedToday)", label: L10n.reviewHomeStatsReview)
                miniStat(value: "\(todayCapture?.cardCount ?? 0)", label: L10n.reviewHomeStatsCaptured)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(SoftPressButtonStyle(pressedScale: 0.99, pressedOpacity: 0.92))
        .accessibilityLabel(L10n.reviewHomeQuotaLink)
    }

    private func miniStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(AppFont.statValue())
                .foregroundStyle(AppColor.textPrimary)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .font(AppFont.statLabel())
                .foregroundStyle(AppColor.textMuted)
        }
    }

    private var dueHero: some View {
        HStack(alignment: .lastTextBaseline, spacing: AppSpacing.sm) {
            Text("\(dueCount)")
                .font(AppFont.heroValue())
                .foregroundStyle(AppColor.textPrimary)
                .contentTransition(.numericText())
                .accessibilityLabel(L10n.reviewHomeDueCount(dueCount))

            Text(L10n.homeStatDue)
                .font(AppFont.secondary().weight(.medium))
                .foregroundStyle(AppColor.textTertiary)
                .padding(.bottom, 8)

            Spacer(minLength: 0)

            if hasAnyCards, StudyStreakStore.totalStudyDays > 0 {
                Text(L10n.homeStatTotalDays(StudyStreakStore.totalStudyDays))
                    .font(AppFont.helper())
                    .foregroundStyle(AppColor.textMuted)
                    .padding(.bottom, 6)
            }
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

    private var emptyCTA: some View {
        Button {
            AppTab.request(.create)
        } label: {
            Text(L10n.reviewEmptyStartCreate)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryButtonStyle(prominent: true))
    }

    private func literaryZone(_ reflection: DailyReflection) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: 6) {
                Text(L10n.reviewDailyTitle)
                    .font(AppFont.helper())
                    .foregroundStyle(AppColor.textMuted)
                Text("·")
                    .font(AppFont.helper())
                    .foregroundStyle(AppColor.textMuted.opacity(0.45))
                Text(seasonLabel(for: reflection))
                    .font(AppFont.helper())
                    .foregroundStyle(AppColor.textMuted.opacity(0.7))
                    .lineLimit(1)
                if let preferenceLabel = DailyReflectionPreferences.promptSnippet {
                    Text("·")
                        .font(AppFont.helper())
                        .foregroundStyle(AppColor.textMuted.opacity(0.45))
                    Text(preferenceLabel)
                        .font(AppFont.helper())
                        .foregroundStyle(AppColor.accent.opacity(0.8))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Button {
                    onShowReflectionPreferences()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(
                            DailyReflectionPreferences.hasKeywords
                                ? AppColor.accent.opacity(0.85)
                                : AppColor.textMuted.opacity(0.55)
                        )
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.reviewDailyPreferencesLink)
                Button(action: onRefreshReflection) {
                    Group {
                        if isRefreshingReflection {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                    .foregroundStyle(AppColor.textMuted.opacity(0.55))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isRefreshingReflection)
                .accessibilityLabel(L10n.reviewDailyRefresh)
            }

            LiteraryQuoteLines(text: reflection.displaySentence)

            if let quoteSource = reflection.quoteSourceAttribution {
                Text("— \(quoteSource)")
                    .font(AppFont.helper())
                    .foregroundStyle(AppColor.textMuted)
            }

            if let translation = reflection.displayTranslation {
                LiteraryQuoteLines(
                    text: translation,
                    font: AppFont.secondary(),
                    foreground: AppColor.textSecondary,
                    lineSpacing: 4
                )
            }

            if let translationSource = reflection.translationSourceAttribution {
                Text("— \(translationSource)")
                    .font(AppFont.helper())
                    .foregroundStyle(AppColor.textMuted)
            }

            HStack(spacing: AppSpacing.md) {
                TextLinkAction(title: isCollectingReflection ? L10n.reviewDailyCollecting : L10n.reviewDailyCollect) {
                    guard !isCollectingReflection else { return }
                    onCollectReflection(reflection)
                }
                .opacity(isCollectingReflection ? 0.6 : 1)
                TextLinkAction(title: L10n.reviewDailyHistoryLink, tone: .muted) {
                    onShowReflectionHistory()
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, AppSpacing.sm)
    }

    private func seasonLabel(for reflection: DailyReflection) -> String {
        let occasion = reflection.occasion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !occasion.isEmpty { return occasion }
        return DailyReflectionPrompt.occasionLabel(for: .now)
    }
}

private struct ReviewQuotaDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let plan: ReviewQueuePlan
    let lifetimeStudiedCount: Int

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

                    AppSurfaceCard {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.reviewHomeLifetimeStudied)
                                .font(AppFont.caption())
                                .foregroundStyle(AppColor.textSecondary)
                            Text("\(lifetimeStudiedCount)")
                                .font(AppFont.statValue())
                                .foregroundStyle(AppColor.textPrimary)
                                .monospacedDigit()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
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
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
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

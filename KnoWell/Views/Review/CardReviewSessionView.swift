import SwiftUI
import SwiftData
import Combine
#if canImport(UIKit)
import UIKit
#endif

struct CardReviewSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var shareImport: ShareImportCoordinator

    let cards: [FlashCard]
    var dismissWhenComplete: Bool = false
    var showDeckName: Bool = false
    var onSessionComplete: (() -> Void)? = nil

    @State private var sessionQueue: [FlashCard] = []
    @State private var pendingLearning: [PendingLearningCard] = []
    @State private var currentIndex = 0
    @State private var showBack = false
    @State private var now = Date()
    @State private var dragOffset: CGSize = .zero
    @State private var editingCard: FlashCard?
    @State private var showCardActions = false
    @State private var showRegenerateConfirm = false
    @State private var isRegenerating = false
    /// Bumps when card content changes so the face re-renders without resetting the queue.
    @State private var contentRevision = 0

    @AppStorage("review.hasSeenSwipeCoach") private var hasSeenSwipeCoach = false
    @State private var showSwipeCoach = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// Library push uses dismiss; Review tab uses onSessionComplete — both get the same back chrome.
    private var canLeaveSession: Bool { dismissWhenComplete || onSessionComplete != nil }

    var body: some View {
        Group {
            if let card = currentCard {
                reviewContent(for: card)
                    .id("\(card.id)-\(contentRevision)")
            } else if let nextLearningDate = pendingLearning.map(\.availableAt).min() {
                learningWaitState(nextAvailable: nextLearningDate)
            } else {
                sessionFinishedState
            }
        }
        // One shared study chrome: never use the system nav title (avoids Library showing the word as page title).
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: Binding(
            get: { editingCard != nil },
            set: { if !$0 { editingCard = nil } }
        )) {
            if let card = editingCard {
                FlashCardEditSheet(card: card) {
                    contentRevision &+= 1
                }
            }
        }
        .appActionSheet(
            isPresented: $showCardActions,
            actions: currentCardActions
        )
        .appConfirmSheet(
            isPresented: $showRegenerateConfirm,
            title: L10n.cardRegenerate,
            message: L10n.cardRegenerateMessage,
            confirmTitle: L10n.cardRegenerate,
            confirmRole: .accent
        ) {
            Task { await regenerateCurrentCard() }
        }
        .loadingOverlay(isPresented: isRegenerating, message: L10n.cardRegenerateRunning)
        .onAppear {
            syncSessionQueue(with: cards)
            prepareRevealState(for: currentCard)
        }
        .onChange(of: cards.map(\.id)) { _, _ in
            syncSessionQueue(with: cards)
        }
        .onChange(of: currentCard?.id) { _, _ in
            prepareRevealState(for: currentCard)
        }
        .onReceive(timer) { date in
            now = date
            promoteReadyLearningCards()
        }
    }

    @ViewBuilder
    private var sessionFinishedState: some View {
        VStack(spacing: AppSpacing.md) {
            if canLeaveSession {
                sessionTopBar(trailing: EmptyView())
            }
            AppEmptyState(
                title: L10n.noCardsToReview,
                message: L10n.reviewEmptyDone,
                systemImage: "checkmark.circle",
                actionTitle: canLeaveSession ? (dismissWhenComplete ? L10n.done : L10n.reviewHomeBack) : nil,
                action: canLeaveSession ? { leaveSession() } : nil
            )
        }
    }

    private func leaveSession() {
        if dismissWhenComplete {
            dismiss()
        } else {
            onSessionComplete?()
        }
    }

    private var currentCard: FlashCard? {
        guard sessionQueue.indices.contains(currentIndex) else { return nil }
        return sessionQueue[currentIndex]
    }

    private func shouldAutoRevealAnswer(for card: FlashCard) -> Bool {
        card.cardType == .appreciation
    }

    private func prepareRevealState(for card: FlashCard?) {
        showBack = card.map(shouldAutoRevealAnswer(for:)) ?? false
        maybePresentSwipeCoach(for: card)
    }

    private func maybePresentSwipeCoach(for card: FlashCard?) {
        guard !hasSeenSwipeCoach, let card, showBack || shouldAutoRevealAnswer(for: card) else { return }
        showSwipeCoach = true
    }

    private var swipeCoachOverlay: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture { dismissSwipeCoach() }

            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text(L10n.reviewSwipeCoachTitle)
                    .font(AppFont.sectionTitle())
                    .foregroundStyle(AppColor.textPrimary)

                coachRow(icon: "arrow.down", text: L10n.reviewSwipeCoachReveal)
                coachRow(icon: "arrow.left", text: L10n.reviewSwipeCoachAgain)
                coachRow(icon: "arrow.right", text: L10n.reviewSwipeCoachEasy)
                coachRow(icon: "hand.tap", text: L10n.reviewSwipeCoachGood)

                Button(action: dismissSwipeCoach) {
                    Text(L10n.reviewSwipeCoachGotIt)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(prominent: true))
                .padding(.top, AppSpacing.xs)
            }
            .padding(AppSpacing.lg)
            .background(AppColor.surface, in: RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
            .appSoftShadow()
            .padding(.horizontal, AppSpacing.lg)
        }
        .accessibilityElement(children: .contain)
    }

    private func coachRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(AppColor.accent)
                .frame(width: 22)
            Text(text)
                .font(AppFont.secondary())
                .foregroundStyle(AppColor.textBody)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func dismissSwipeCoach() {
        hasSeenSwipeCoach = true
        showSwipeCoach = false
    }

    private func reviewContent(for card: FlashCard) -> some View {
        VStack(spacing: 0) {
            sessionTopBar(trailing: topTrailingActions(for: card))

            if showDeckName, let deckName = card.deck?.name, !deckName.isEmpty {
                Text(deckName)
                    .font(AppFont.caption())
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.bottom, AppSpacing.xs)
            }

            CardStudyFaceView(
                content: card.studyContent,
                showBack: $showBack,
                dragOffset: $dragOffset,
                allowsReviewGestures: true,
                onHighlight: { term in
                    card.highlightText = term
                    contentRevision &+= 1
                    ToastCenter.shared.show(L10n.studySelectionHighlightUpdated)
                },
                onCreateCard: { term in
                    shareImport.importPayload(
                        ShareImportPayload(
                            sentence: card.sentence,
                            selectedWord: term,
                            source: .clipboard
                        )
                    )
                    AppTab.request(.create)
                },
                onRevealed: {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        maybePresentSwipeCoach(for: card)
                    }
                },
                onSwipeAgain: { submit(rating: .again, for: card) },
                onSwipeEasy: { submit(rating: .easy, for: card) }
            )
        }
        .overlay {
            if showSwipeCoach {
                swipeCoachOverlay
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: showSwipeCoach)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showBack {
                ratingButtons(for: card)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    private func sessionTopBar<Trailing: View>(trailing: Trailing) -> some View {
        HStack(spacing: AppSpacing.sm) {
            if canLeaveSession {
                Button {
                    leaveSession()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppColor.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(AppColor.surface, in: Circle())
                        .appSoftShadow()
                }
                .buttonStyle(SoftPressButtonStyle())
                .accessibilityLabel(L10n.back)
            }

            Text(L10n.reviewProgress(currentIndex + 1, max(sessionQueue.count, 1)))
                .font(AppFont.helper())
                .foregroundStyle(AppColor.textMuted)
                .monospacedDigit()

            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.top, AppSpacing.sm)
        .padding(.bottom, AppSpacing.xs)
    }

    private func topTrailingActions(for card: FlashCard) -> some View {
        Button {
            showCardActions = true
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(AppColor.textPrimary)
                .frame(width: 40, height: 40)
                .background(AppColor.surface, in: Circle())
                .appSoftShadow()
        }
        .buttonStyle(SoftPressButtonStyle())
        .accessibilityLabel(L10n.libraryEdit)
    }

    private var currentCardActions: [AppSheetAction] {
        [
            AppSheetAction(title: L10n.libraryEdit, systemImage: "pencil") {
                editingCard = currentCard
            },
            AppSheetAction(
                title: L10n.cardRegenerate,
                systemImage: "sparkles",
                role: .accent,
                isEnabled: APISettings.canUseAI && !isRegenerating
            ) {
                showRegenerateConfirm = true
            }
        ]
    }

    @MainActor
    private func regenerateCurrentCard() async {
        guard let card = currentCard else { return }
        isRegenerating = true
        defer { isRegenerating = false }
        do {
            try await CardContentRegenerator.regenerate(card)
            contentRevision &+= 1
            ToastCenter.shared.show(L10n.cardRegenerateDone)
        } catch {
            ToastCenter.shared.show(error.localizedDescription)
        }
    }

    private func learningWaitState(nextAvailable: Date) -> some View {
        VStack(spacing: AppSpacing.md) {
            if canLeaveSession {
                sessionTopBar(trailing: EmptyView())
            }
            AppEmptyState(
                title: L10n.reviewLearningWaitTitle,
                message: L10n.reviewLearningWaitMessage(ReviewScheduler.formatInterval(from: now, to: nextAvailable)),
                systemImage: "clock",
                actionTitle: canLeaveSession ? (dismissWhenComplete ? L10n.done : L10n.reviewHomeBack) : nil,
                action: canLeaveSession ? { leaveSession() } : nil
            )
        }
    }

    private func ratingButtons(for card: FlashCard) -> some View {
        HStack(spacing: AppSpacing.sm) {
            ForEach(ReviewRating.userChoices, id: \.rawValue) { rating in
                Button {
                    submit(rating: rating, for: card)
                } label: {
                    HStack(spacing: 4) {
                        Text(rating.displayTitle(for: card.cardType))
                            .font(.subheadline.weight(.semibold))
                        Text(ReviewScheduler.intervalLabel(for: card, rating: rating, now: now))
                            .font(AppFont.weak())
                            .opacity(0.85)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(ReviewRatingButtonStyle(rating: rating))
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.top, AppSpacing.xs)
        .padding(.bottom, AppSpacing.sm)
        .background(AppColor.pageBackground.opacity(0.96))
    }

    private func submit(rating: ReviewRating, for card: FlashCard) {
        playRatingHaptic(rating)
        let preview = ReviewScheduler.preview(rating: rating, for: card, now: now)
        ReviewScheduler.apply(rating: rating, to: card, now: now)
        StudyStreakStore.recordStudy(now: now)
        NotificationCenter.default.post(name: .reviewQueueDidChange, object: nil)
        showBack = false
        dragOffset = .zero

        sessionQueue.removeAll { $0.id == card.id }

        if ReviewScheduler.isLearningDelay(preview, now: now) {
            pendingLearning.append(PendingLearningCard(card: card, availableAt: preview.nextReviewDate))
        }

        if sessionQueue.isEmpty {
            promoteReadyLearningCards()
        }

        if sessionQueue.isEmpty {
            if dismissWhenComplete, pendingLearning.isEmpty {
                dismiss()
            }
            return
        }

        if currentIndex >= sessionQueue.count {
            currentIndex = max(0, sessionQueue.count - 1)
        }
        prepareRevealState(for: currentCard)
    }

    private func playRatingHaptic(_ rating: ReviewRating) {
        #if canImport(UIKit)
        let style: UIImpactFeedbackGenerator.FeedbackStyle
        switch rating {
        case .again:
            style = .medium
        case .hard, .good, .easy:
            style = .light
        }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
        #endif
    }

    private func syncSessionQueue(with cards: [FlashCard]) {
        let pendingIDs = Set(pendingLearning.map(\.card.id))

        if sessionQueue.isEmpty {
            let initial = cards.filter { !pendingIDs.contains($0.id) }
            sessionQueue = ReviewQueueBuilder.shuffledAvoidingAdjacentSameWord(initial)
            currentIndex = 0
            return
        }

        let existingIDs = Set(sessionQueue.map(\.id))
        for card in cards where !pendingIDs.contains(card.id) && !existingIDs.contains(card.id) {
            insertAvoidingSameWord(card)
        }

        if currentIndex >= sessionQueue.count {
            currentIndex = max(0, sessionQueue.count - 1)
        }
    }

    private func promoteReadyLearningCards() {
        let ready = pendingLearning.filter { $0.availableAt <= now }.map(\.card)
        guard !ready.isEmpty else { return }

        pendingLearning.removeAll { $0.availableAt <= now }
        for card in ReviewQueueBuilder.shuffledAvoidingAdjacentSameWord(ready) {
            insertAvoidingSameWord(card)
        }

        if currentIndex >= sessionQueue.count {
            currentIndex = max(0, sessionQueue.count - 1)
        }
        prepareRevealState(for: currentCard)
    }

    /// Insert after the current card when possible, skipping spots that would put
    /// the same word or sentence back-to-back.
    private func insertAvoidingSameWord(_ card: FlashCard) {
        if sessionQueue.isEmpty {
            sessionQueue.append(card)
            return
        }

        let start = min(currentIndex + 1, sessionQueue.count)

        if let index = (start...sessionQueue.count).first(where: { insertionIndex in
            let beforeOK = insertionIndex == 0
                || !ReviewQueueBuilder.sharesStudyContext(sessionQueue[insertionIndex - 1], with: card)
            let afterOK = insertionIndex == sessionQueue.count
                || !ReviewQueueBuilder.sharesStudyContext(sessionQueue[insertionIndex], with: card)
            return beforeOK && afterOK
        }) {
            sessionQueue.insert(card, at: index)
        } else {
            sessionQueue.append(card)
        }
    }
}

private struct PendingLearningCard: Identifiable {
    let card: FlashCard
    let availableAt: Date

    var id: UUID { card.id }
}

struct ReviewRatingButtonStyle: ButtonStyle {
    let rating: ReviewRating

    func makeBody(configuration: Configuration) -> some View {
        let palette = palette(for: rating)
        configuration.label
            .foregroundStyle(palette.foreground)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous)
                    .fill(palette.background.opacity(configuration.isPressed ? 1.12 : 1))
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous)
                    .strokeBorder(palette.border.opacity(configuration.isPressed ? 0.8 : 0.9), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }

    private func palette(for rating: ReviewRating) -> (background: Color, border: Color, foreground: Color) {
        switch rating {
        case .again:
            (
                AppColor.ratingAgainBackground(),
                AppColor.danger.opacity(0.28),
                AppColor.danger
            )
        case .hard:
            (
                AppColor.ratingHardBackground(),
                AppColor.warning.opacity(0.32),
                AppColor.warning
            )
        case .good:
            (
                AppColor.surfaceMuted,
                AppColor.border,
                AppColor.accentStrong
            )
        case .easy:
            (
                AppColor.ratingEasyBackground(),
                AppColor.success.opacity(0.28),
                AppColor.success
            )
        }
    }
}

#Preview {
    NavigationStack {
        CardReviewSessionView(cards: [])
            .navigationTitle(L10n.studyTitle)
    }
    .environment(ReviewSettingsStore.shared)
    .environmentObject(ShareImportCoordinator())
    .modelContainer(for: FlashCard.self, inMemory: true)
}

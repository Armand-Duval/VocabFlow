import SwiftUI
import SwiftData
import Combine
#if canImport(UIKit)
import UIKit
#endif

struct CardReviewSessionView: View {
    @Environment(\.dismiss) private var dismiss

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

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let swipeThreshold: CGFloat = 72

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
        }
        .onChange(of: cards.map(\.id)) { _, _ in
            syncSessionQueue(with: cards)
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

    private func reviewContent(for card: FlashCard) -> some View {
        VStack(spacing: AppSpacing.sm) {
            sessionTopBar(trailing: cardActions(for: card))

            // Word sits directly above the card (study content), not in nav chrome.
            HStack(alignment: .center, spacing: AppSpacing.sm) {
                if showBack || card.cardType == .definition {
                    wordHeader(for: card)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                } else {
                    Text(L10n.cardTypeCloze)
                        .font(AppFont.caption())
                        .foregroundStyle(AppColor.textTertiary)
                        .transition(.opacity)
                }

                Spacer(minLength: 0)
                speakButton(for: card)
            }
            .padding(.horizontal, AppSpacing.md)
            .animation(Self.cardFlipAnimation, value: showBack)

            if showDeckName, let deckName = card.deck?.name, !deckName.isEmpty {
                Text(deckName)
                    .font(AppFont.caption())
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppSpacing.md)
            }

            cardFace(card)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(x: dragOffset.width * 0.25)
                .gesture(swipeGesture(for: card))

            if showBack {
                ratingButtons(for: card)
                    .padding(.bottom, AppSpacing.xs)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                Button {
                    flipCard(toBack: true)
                } label: {
                    Label(L10n.showAnswer, systemImage: "eye")
                }
                .buttonStyle(RevealAnswerButtonStyle())
                .padding(.horizontal, AppSpacing.md)
                .padding(.bottom, AppSpacing.sm)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(Self.cardFlipAnimation, value: showBack)
    }

    private static let cardFlipAnimation: Animation = .spring(response: 0.48, dampingFraction: 0.86)

    private func flipCard(toBack: Bool? = nil) {
        withAnimation(Self.cardFlipAnimation) {
            if let toBack {
                showBack = toBack
            } else {
                showBack.toggle()
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
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.back)
            }

            Text(L10n.reviewProgress(currentIndex + 1, max(sessionQueue.count, 1)))
                .font(AppFont.weak())
                .foregroundStyle(AppColor.textTertiary)

            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.top, AppSpacing.sm)
    }

    private func cardActions(for card: FlashCard) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Text(card.cardType.displayName)
                .font(AppFont.weak())
                .foregroundStyle(AppColor.textTertiary)

            Button {
                showCardActions = true
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(AppColor.surface, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.libraryEdit)
        }
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

    @ViewBuilder
    private func wordHeader(for card: FlashCard) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(card.word)
                .font(AppFont.studyWord())
                .foregroundStyle(AppColor.accent)

            if let phonetic = card.phonetic?.trimmingCharacters(in: .whitespacesAndNewlines),
               !phonetic.isEmpty {
                Text(phonetic.hasPrefix("/") || phonetic.hasPrefix("[") ? phonetic : "/\(phonetic)/")
                    .font(AppFont.secondary())
                    .foregroundStyle(AppColor.textSecondary)
                    .textSelection(.enabled)
            }
        }
    }

    private func speakButton(for card: FlashCard) -> some View {
        Button {
            SpeechService.speak(card.word)
        } label: {
            Image(systemName: "speaker.wave.2.fill")
                .font(.title3)
                .frame(width: 40, height: 40)
                .foregroundStyle(AppColor.accent)
                .background(AppColor.accentBackground(0.12), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.speakWord)
    }

    private func cardFace(_ card: FlashCard) -> some View {
        ZStack {
            cardFacePanel {
                cardFrontContent(for: card)
            }
            .opacity(showBack ? 0 : 1)
            .rotation3DEffect(
                .degrees(showBack ? 180 : 0),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.65
            )
            .allowsHitTesting(!showBack)

            cardFacePanel {
                cardBackContent(for: card)
            }
            .opacity(showBack ? 1 : 0)
            .rotation3DEffect(
                .degrees(showBack ? 0 : -180),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.65
            )
            .allowsHitTesting(showBack)
        }
        .padding(.horizontal, AppSpacing.md)
        .onTapGesture {
            flipCard()
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(showBack ? L10n.backLabel : L10n.frontLabel)
    }

    private func cardFacePanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            content()
                .lineSpacing(8)
                .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
                .textSelection(.enabled)
                .padding(AppSpacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
    }

    @ViewBuilder
    private func cardFrontContent(for card: FlashCard) -> some View {
        if card.cardType == .definition {
            HighlightedText(
                text: card.displayFront,
                query: card.word,
                font: AppFont.body()
            )
            .foregroundStyle(AppColor.textPrimary)
        } else {
            Text(card.displayFront)
                .font(AppFont.body())
                .foregroundStyle(AppColor.textPrimary)
        }
    }

    @ViewBuilder
    private func cardBackContent(for card: FlashCard) -> some View {
        let sense = CardContentFormatter.senseText(card.back)
        let translation = CardContentFormatter.sentenceTranslation(card.contextNote)
        let highlightTerms = CardContentFormatter.translationHighlightTerms(
            contextNote: card.contextNote,
            sense: sense
        )

        if let translation, !sense.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text(sense)
                    .font(AppFont.body())
                    .foregroundStyle(AppColor.textPrimary)

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.cardSentenceTranslation)
                        .font(AppFont.weak())
                        .foregroundStyle(AppColor.textTertiary)
                    HighlightedText(
                        text: translation,
                        terms: highlightTerms,
                        font: AppFont.body(),
                        emphasizeForeground: true
                    )
                    .foregroundStyle(AppColor.textBody)
                }

                if let source = card.sourceAttribution?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !source.isEmpty {
                    Text(L10n.cardSource(source))
                        .font(AppFont.weak())
                        .foregroundStyle(AppColor.textTertiary)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text(card.displayBack)
                    .font(AppFont.body())
                    .foregroundStyle(AppColor.textPrimary)
                if let source = card.sourceAttribution?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !source.isEmpty {
                    Text(L10n.cardSource(source))
                        .font(AppFont.weak())
                        .foregroundStyle(AppColor.textTertiary)
                }
            }
        }
    }

    private func swipeGesture(for card: FlashCard) -> some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                guard showBack else { return }
                dragOffset = value.translation
            }
            .onEnded { value in
                guard showBack else {
                    dragOffset = .zero
                    return
                }

                defer { dragOffset = .zero }

                if value.translation.width <= -swipeThreshold {
                    submit(rating: .again, for: card)
                } else if value.translation.width >= swipeThreshold {
                    submit(rating: .easy, for: card)
                } else if value.translation.height >= swipeThreshold {
                    submit(rating: .good, for: card)
                }
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
                    VStack(spacing: 4) {
                        Text(rating.title)
                            .font(.subheadline.weight(.semibold))
                        Text(ReviewScheduler.intervalLabel(for: card, rating: rating, now: now))
                            .font(AppFont.caption())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.sm)
                }
                .buttonStyle(ReviewRatingButtonStyle(rating: rating))
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.bottom, AppSpacing.xs)
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
    }

    private func playRatingHaptic(_ rating: ReviewRating) {
        #if canImport(UIKit)
        let style: UIImpactFeedbackGenerator.FeedbackStyle
        switch rating {
        case .again, .hard:
            style = .medium
        case .good, .easy:
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
        showBack = false
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

private struct ReviewRatingButtonStyle: ButtonStyle {
    let rating: ReviewRating

    func makeBody(configuration: Configuration) -> some View {
        let palette = palette(for: rating)
        configuration.label
            .foregroundStyle(palette.foreground)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous)
                    .fill(palette.background.opacity(configuration.isPressed ? 1.15 : 1))
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous)
                    .strokeBorder(palette.border.opacity(configuration.isPressed ? 0.85 : 1), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }

    private func palette(for rating: ReviewRating) -> (background: Color, border: Color, foreground: Color) {
        switch rating {
        case .again:
            (
                AppColor.ratingAgainBackground(),
                AppColor.danger.opacity(0.35),
                AppColor.danger
            )
        case .hard:
            (
                AppColor.ratingHardBackground(),
                AppColor.warning.opacity(0.4),
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
                AppColor.success.opacity(0.35),
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
    .modelContainer(for: FlashCard.self, inMemory: true)
}

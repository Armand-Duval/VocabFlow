import SwiftUI
import SwiftData
import Combine

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

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let swipeThreshold: CGFloat = 72

    var body: some View {
        Group {
            if let card = currentCard {
                reviewContent(for: card)
            } else if let nextLearningDate = pendingLearning.map(\.availableAt).min() {
                learningWaitState(nextAvailable: nextLearningDate)
            } else {
                AppEmptyState(
                    title: L10n.noCardsToReview,
                    message: L10n.reviewEmptyDone,
                    systemImage: "checkmark.circle",
                    actionTitle: onSessionComplete == nil ? nil : L10n.reviewHomeBack,
                    action: onSessionComplete
                )
            }
        }
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

    private var currentCard: FlashCard? {
        guard sessionQueue.indices.contains(currentIndex) else { return nil }
        return sessionQueue[currentIndex]
    }

    private func reviewContent(for card: FlashCard) -> some View {
        VStack(spacing: AppSpacing.sm) {
            progressHeader(for: card)

            HStack(alignment: .center, spacing: AppSpacing.sm) {
                if showBack || card.cardType == .definition {
                    // Definition: word title + sentence body. Cloze: hide word until revealed.
                    wordHeader(for: card)
                } else {
                    Text(L10n.cardTypeCloze)
                        .font(AppFont.caption())
                        .foregroundStyle(AppColor.textTertiary)
                }

                Spacer(minLength: 0)
                speakButton(for: card)
            }
            .padding(.horizontal, AppSpacing.md)

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
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showBack = true
                    }
                } label: {
                    Label(L10n.showAnswer, systemImage: "eye")
                }
                .buttonStyle(RevealAnswerButtonStyle())
                .padding(.horizontal, AppSpacing.md)
                .padding(.bottom, AppSpacing.sm)
            }
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

    private func progressHeader(for card: FlashCard) -> some View {
        HStack {
            Text(L10n.reviewProgress(currentIndex + 1, sessionQueue.count))
                .font(AppFont.weak())
                .foregroundStyle(AppColor.textTertiary)

            Spacer()

            Text(card.cardType.displayName)
                .font(AppFont.weak())
                .foregroundStyle(AppColor.textTertiary)
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.top, AppSpacing.sm)
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
        ScrollView {
            Group {
                if showBack {
                    cardBackContent(for: card)
                } else if card.cardType == .definition {
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
            .lineSpacing(8)
            .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
            .textSelection(.enabled)
            .contentTransition(.opacity)
            .padding(AppSpacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
        .padding(.horizontal, AppSpacing.md)
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                showBack.toggle()
            }
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
        AppEmptyState(
            title: L10n.reviewLearningWaitTitle,
            message: L10n.reviewLearningWaitMessage(ReviewScheduler.formatInterval(from: now, to: nextAvailable)),
            systemImage: "clock"
        )
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

    private func syncSessionQueue(with cards: [FlashCard]) {
        let pendingIDs = Set(pendingLearning.map(\.card.id))
        let existingIDs = Set(sessionQueue.map(\.id))

        for card in cards where !pendingIDs.contains(card.id) && !existingIDs.contains(card.id) {
            sessionQueue.append(card)
        }

        if currentIndex >= sessionQueue.count {
            currentIndex = max(0, sessionQueue.count - 1)
        }
    }

    private func promoteReadyLearningCards() {
        let ready = pendingLearning.filter { $0.availableAt <= now }
        guard !ready.isEmpty else { return }

        pendingLearning.removeAll { $0.availableAt <= now }
        sessionQueue.append(contentsOf: ready.map(\.card))

        if currentIndex >= sessionQueue.count {
            currentIndex = max(0, sessionQueue.count - 1)
        }
        showBack = false
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

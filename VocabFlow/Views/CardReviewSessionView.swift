import SwiftUI
import SwiftData
import Combine

struct CardReviewSessionView: View {
    @Environment(\.dismiss) private var dismiss

    let cards: [FlashCard]
    var dismissWhenComplete: Bool = false

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
                    systemImage: "tray"
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
            HStack {
                Text(L10n.reviewProgress(currentIndex + 1, sessionQueue.count))
                    .font(AppFont.captionSecondary())
                    .foregroundStyle(.secondary)
                Spacer()
                CardTypeChip(title: card.cardType.displayName)
            }
            .padding(.horizontal, AppSpacing.md)

            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                Text(card.word)
                    .font(AppFont.sectionTitle())

                if let phonetic = card.phonetic, !phonetic.isEmpty {
                    Text(phonetic)
                        .font(AppFont.secondary())
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Menu {
                    Button(L10n.speakWord) {
                        SpeechService.speak(card.word)
                    }
                    Button(L10n.speakSentence) {
                        SpeechService.speak(card.sentence)
                    }
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                        .foregroundStyle(AppColor.accent)
                }
                .accessibilityLabel(L10n.speakWord)
            }
            .padding(.horizontal, AppSpacing.md)

            cardFace(card)
                .offset(x: dragOffset.width * 0.25)
                .gesture(swipeGesture(for: card))

            if showBack {
                ratingButtons(for: card)
                Text(L10n.reviewSwipeHint)
                    .font(AppFont.caption())
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.md)
            } else {
                Button(L10n.showAnswer) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showBack = true
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, AppSpacing.md)
                .padding(.bottom, AppSpacing.xs)
            }
        }
    }

    private func cardFace(_ card: FlashCard) -> some View {
        ScrollView {
            Text(showBack ? card.displayBack : card.front)
                .font(AppFont.body())
                .lineSpacing(6)
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .contentTransition(.opacity)
                .padding(AppSpacing.lg)
        }
        .frame(maxHeight: 340)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
        .padding(.horizontal, AppSpacing.md)
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                showBack.toggle()
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
                } else if value.translation.height <= -swipeThreshold {
                    submit(rating: .hard, for: card)
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
        VStack(spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.sm) {
                ForEach(ReviewRating.allCases, id: \.rawValue) { rating in
                    Button {
                        submit(rating: rating, for: card)
                    } label: {
                        VStack(spacing: 4) {
                            Text(rating.title)
                                .fontWeight(.semibold)
                            Text(ReviewScheduler.intervalLabel(for: card, rating: rating, now: now))
                                .font(AppFont.caption())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.sm)
                    }
                    .buttonStyle(ReviewRatingButtonStyle())
                    .tint(ratingTint(rating))
                }
            }

            Text(L10n.reviewRatingHint)
                .font(AppFont.caption())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.bottom, AppSpacing.xs)
    }

    private func ratingTint(_ rating: ReviewRating) -> Color {
        switch rating {
        case .again: .red
        case .hard: .orange
        case .good: AppColor.accent
        case .easy: .green
        }
    }

    private func submit(rating: ReviewRating, for card: FlashCard) {
        let preview = ReviewScheduler.preview(rating: rating, for: card, now: now)
        ReviewScheduler.apply(rating: rating, to: card, now: now)
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
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous)
                    .fill(configuration.isPressed ? AppColor.accentBackground(0.14) : Color.clear)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous)
                    .strokeBorder(.secondary.opacity(configuration.isPressed ? 0.5 : 0.25))
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview {
    NavigationStack {
        CardReviewSessionView(cards: [])
            .navigationTitle(L10n.studyTitle)
    }
    .modelContainer(for: FlashCard.self, inMemory: true)
}

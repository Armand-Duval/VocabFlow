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

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if let card = currentCard {
                reviewContent(for: card)
            } else if let nextLearningDate = pendingLearning.map(\.availableAt).min() {
                learningWaitState(nextAvailable: nextLearningDate)
            } else {
                ContentUnavailableView {
                    Label(L10n.noCardsToReview, systemImage: "tray")
                }
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
        VStack(spacing: 12) {
            HStack {
                Text(L10n.reviewProgress(currentIndex + 1, sessionQueue.count))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(card.cardType.displayName)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.blue.opacity(0.12))
                    .clipShape(Capsule())
            }
            .padding(.horizontal)

            ScrollView {
                Text(showBack ? card.displayBack : card.front)
                    .font(.body)
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .contentTransition(.opacity)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal)
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showBack.toggle()
                }
            }

            if showBack {
                ratingButtons(for: card)
            } else {
                Button(L10n.showAnswer) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showBack = true
                    }
                }
                .buttonStyle(.borderedProminent)
                .padding(.bottom, 8)
            }
        }
    }

    private func learningWaitState(nextAvailable: Date) -> some View {
        ContentUnavailableView {
            Label(L10n.reviewLearningWaitTitle, systemImage: "clock")
        } description: {
            Text(L10n.reviewLearningWaitMessage(ReviewScheduler.formatInterval(from: now, to: nextAvailable)))
        }
    }

    private func ratingButtons(for card: FlashCard) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                ForEach(ReviewRating.allCases, id: \.rawValue) { rating in
                    Button {
                        submit(rating: rating, for: card)
                    } label: {
                        VStack(spacing: 4) {
                            Text(rating.title)
                                .fontWeight(.semibold)
                            Text(ReviewScheduler.intervalLabel(for: card, rating: rating, now: now))
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .tint(ratingTint(rating))
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private func ratingTint(_ rating: ReviewRating) -> Color {
        switch rating {
        case .again: .red
        case .hard: .orange
        case .good: .blue
        case .easy: .green
        }
    }

    private func submit(rating: ReviewRating, for card: FlashCard) {
        let preview = ReviewScheduler.preview(rating: rating, for: card, now: now)
        ReviewScheduler.apply(rating: rating, to: card, now: now)
        showBack = false

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

#Preview {
    NavigationStack {
        CardReviewSessionView(cards: [])
            .navigationTitle(L10n.studyTitle)
    }
    .modelContainer(for: FlashCard.self, inMemory: true)
}

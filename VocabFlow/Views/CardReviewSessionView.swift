import SwiftUI
import SwiftData

struct CardReviewSessionView: View {
    @Environment(\.dismiss) private var dismiss

    let cards: [FlashCard]
    var dismissWhenComplete: Bool = false

    @State private var currentIndex = 0
    @State private var showBack = false

    var body: some View {
        Group {
            if cards.isEmpty {
                ContentUnavailableView {
                    Label(L10n.noCardsToReview, systemImage: "tray")
                }
            } else {
                reviewContent
            }
        }
        .onChange(of: cards.count) { _, newCount in
            if currentIndex >= newCount {
                currentIndex = max(0, newCount - 1)
            }
            showBack = false
        }
    }

    private var reviewContent: some View {
        let card = cards[currentIndex]

        return VStack(spacing: 12) {
            HStack {
                Text("\(currentIndex + 1) / \(cards.count)")
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
                VStack(alignment: .leading, spacing: 12) {
                    Text(showBack ? L10n.cardBack : L10n.cardFront)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(showBack ? card.displayBack : card.front)
                        .font(.body)
                        .lineSpacing(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .contentTransition(.opacity)
                }
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

            Text(showBack ? L10n.tapToFlipBack : L10n.tapToReveal)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

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
                            Text(rating.subtitle)
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
        ReviewScheduler.apply(rating: rating, to: card)
        showBack = false

        if currentIndex < cards.count - 1 {
            currentIndex += 1
        } else if dismissWhenComplete {
            dismiss()
        } else {
            currentIndex = 0
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

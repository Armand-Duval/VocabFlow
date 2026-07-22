import SwiftUI
import SwiftData

struct ReviewView: View {
    @Query(sort: \FlashCard.nextReviewDate) private var allCards: [FlashCard]

    private var dueCards: [FlashCard] {
        allCards.filter { ReviewScheduler.isDue($0) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if dueCards.isEmpty {
                    emptyState
                } else {
                    CardReviewSessionView(cards: dueCards)
                }
            }
            .navigationTitle(L10n.reviewTitle)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(L10n.reviewEmptyTitle, systemImage: "checkmark.circle")
        } description: {
            Text(allCards.isEmpty ? L10n.reviewEmptyNoCards : L10n.reviewEmptyDone)
        }
    }
}

#Preview {
    ReviewView()
        .modelContainer(for: FlashCard.self, inMemory: true)
}

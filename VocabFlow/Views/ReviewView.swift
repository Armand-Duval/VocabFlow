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
            .navigationTitle("复习")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("暂无待复习", systemImage: "checkmark.circle")
        } description: {
            Text(allCards.isEmpty ? "先去「制卡」生成并保存卡片。" : "今天的卡片都复习完了。可以去「词库」点卡片继续学习。")
        }
    }
}

#Preview {
    ReviewView()
        .modelContainer(for: FlashCard.self, inMemory: true)
}

import SwiftUI
import SwiftData

struct DeckStatisticsView: View {
    let deck: Deck

    @Environment(\.modelContext) private var modelContext
    @State private var stats: DeckStatistics?

    var body: some View {
        List {
            if let stats {
                Section(L10n.deckStatisticsOverview) {
                    statRow(title: L10n.deckStatisticsTotal, value: "\(stats.totalCards)")
                    statRow(title: L10n.deckStatisticsDue, value: "\(stats.dueCount)")
                    statRow(title: L10n.deckStatisticsNew, value: "\(stats.newCount)")
                    statRow(title: L10n.deckStatisticsLearned, value: "\(stats.learnedCount)")
                    statRow(title: L10n.deckStatisticsMastery, value: L10n.deckStatisticsMasteryValue(stats.masteryRate))
                }
            } else {
                Section {
                    ProgressView(L10n.deckLoading)
                }
            }
        }
        .navigationTitle(deck.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: deck.id) {
            await loadStatistics()
        }
        .onReceive(NotificationCenter.default.publisher(for: .libraryCatalogDidChange)) { _ in
            Task { await loadStatistics() }
        }
    }

    private func statRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    @MainActor
    private func loadStatistics() async {
        await Task.yield()
        stats = DeckStatisticsService.statistics(for: deck, in: modelContext)
    }
}

#Preview {
    NavigationStack {
        DeckStatisticsView(deck: Deck(name: "Preview"))
    }
    .modelContainer(for: [Deck.self, FlashCard.self], inMemory: true)
}

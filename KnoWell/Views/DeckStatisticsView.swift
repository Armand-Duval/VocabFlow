import SwiftUI
import SwiftData

struct DeckStatisticsView: View {
    let deck: Deck

    @Environment(\.modelContext) private var modelContext
    @State private var stats: DeckStatistics?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                if let stats {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.sm) {
                        AppStatTile(title: L10n.deckStatisticsTotal, value: "\(stats.totalCards)")
                        AppStatTile(title: L10n.deckStatisticsDue, value: "\(stats.dueCount)", tint: AppColor.warning)
                        AppStatTile(title: L10n.deckStatisticsNew, value: "\(stats.newCount)", tint: AppColor.accent)
                        AppStatTile(title: L10n.deckStatisticsLearned, value: "\(stats.learnedCount)", tint: AppColor.success)
                    }

                    AppSurfaceCard {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            Text(L10n.deckStatisticsMastery)
                                .font(AppFont.caption())
                                .foregroundStyle(AppColor.textSecondary)

                            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
                                Text(L10n.deckStatisticsMasteryValue(stats.masteryRate))
                                    .font(AppFont.statValue())
                                    .foregroundStyle(AppColor.accent)
                                Spacer()
                            }

                            ProgressView(value: stats.masteryRate)
                                .tint(AppColor.accent)
                        }
                    }
                } else {
                    AppSurfaceCard {
                        HStack {
                            ProgressView()
                                .tint(AppColor.accent)
                            Text(L10n.deckLoading)
                                .font(AppFont.secondary())
                                .foregroundStyle(AppColor.textSecondary)
                        }
                    }
                }
            }
            .padding(AppSpacing.md)
        }
        .appPageBackground()
        .navigationTitle(deck.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: deck.id) {
            await loadStatistics()
        }
        .onReceive(NotificationCenter.default.publisher(for: .libraryCatalogDidChange)) { _ in
            Task { await loadStatistics() }
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

import SwiftUI
import SwiftData

struct LibraryView: View {
    @Query(sort: \FlashCard.createdAt, order: .reverse) private var cards: [FlashCard]
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            Group {
                if cards.isEmpty {
                    ContentUnavailableView {
                        Label(L10n.libraryEmptyTitle, systemImage: "tray")
                    } description: {
                        Text(L10n.libraryEmptyMessage)
                    }
                } else if groupedEntries.isEmpty {
                    ContentUnavailableView {
                        Label(L10n.libraryNoResultsTitle, systemImage: "magnifyingglass")
                    } description: {
                        Text(L10n.libraryNoResultsMessage)
                    }
                } else {
                    List {
                        ForEach(groupedEntries, id: \.word) { entry in
                            Section {
                                ForEach(entry.cards) { card in
                                    NavigationLink {
                                        CardReviewSessionView(cards: [card], dismissWhenComplete: true)
                                            .navigationTitle(entry.word)
                                            .navigationBarTitleDisplayMode(.inline)
                                    } label: {
                                        cardRow(card)
                                    }
                                }
                                .onDelete { offsets in
                                    deleteCards(in: entry.cards, at: offsets)
                                }

                                if entry.cards.count > 1 {
                                    NavigationLink {
                                        CardReviewSessionView(cards: entry.cards, dismissWhenComplete: true)
                                            .navigationTitle(entry.word)
                                            .navigationBarTitleDisplayMode(.inline)
                                    } label: {
                                        Label(
                                            L10n.reviewAll(entry.word, count: entry.cards.count),
                                            systemImage: "brain.head.profile"
                                        )
                                        .font(.subheadline)
                                    }
                                }
                            } header: {
                                Text(entry.word)
                            }
                        }
                    }
                }
            }
            .navigationTitle(L10n.libraryTitle)
            .searchable(text: $searchText, prompt: L10n.librarySearchPrompt)
        }
    }

    private func cardRow(_ card: FlashCard) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(card.cardType.displayName)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.blue.opacity(0.12))
                    .clipShape(Capsule())
                Spacer()
                if ReviewScheduler.isDue(card) {
                    Text(L10n.dueForReview)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                } else {
                    Text(L10n.nextReview(card.nextReviewDate.formatted(date: .abbreviated, time: .shortened)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text(card.front)
                .font(.subheadline)
                .lineLimit(4)

            Text(card.sentence)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }

    private var filteredCards: [FlashCard] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return cards }

        return cards.filter { card in
            card.word.localizedCaseInsensitiveContains(query)
                || card.sentence.localizedCaseInsensitiveContains(query)
                || card.front.localizedCaseInsensitiveContains(query)
                || card.back.localizedCaseInsensitiveContains(query)
                || (card.contextNote?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var groupedEntries: [(word: String, cards: [FlashCard])] {
        let grouped = Dictionary(grouping: filteredCards) { $0.word.lowercased() }
        return grouped
            .map { _, group in
                let sorted = group.sorted { $0.createdAt > $1.createdAt }
                return (word: sorted.first?.word ?? "", cards: sorted)
            }
            .sorted { $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedAscending }
    }

    private func deleteCards(in group: [FlashCard], at offsets: IndexSet) {
        offsets.map { group[$0] }.forEach { modelContext.delete($0) }
    }
}

#Preview {
    LibraryView()
        .modelContainer(for: FlashCard.self, inMemory: true)
}

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
                        Label("词库为空", systemImage: "tray")
                    } description: {
                        Text("保存卡片后会显示在这里。")
                    }
                } else if groupedEntries.isEmpty {
                    ContentUnavailableView {
                        Label("未找到结果", systemImage: "magnifyingglass")
                    } description: {
                        Text("试试搜索其他生词、原句或卡片内容。")
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
                                        Label("复习「\(entry.word)」全部 \(entry.cards.count) 张", systemImage: "brain.head.profile")
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
            .navigationTitle("词库")
            .searchable(text: $searchText, prompt: "搜索生词、原句、卡片内容")
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
                    Text("待复习")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                } else {
                    Text("下次：\(card.nextReviewDate.formatted(date: .abbreviated, time: .shortened))")
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

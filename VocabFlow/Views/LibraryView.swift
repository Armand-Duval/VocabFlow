import SwiftUI
import SwiftData

struct LibraryView: View {
    @Query(sort: \FlashCard.createdAt, order: .reverse) private var allCards: [FlashCard]
    @Query(sort: [SortDescriptor(\Deck.sortOrder), SortDescriptor(\Deck.createdAt)])
    private var decks: [Deck]

    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var filterDeckID: UUID?
    @State private var selectedDeckID: UUID?

    private var cards: [FlashCard] {
        guard let filterDeckID else { return allCards }
        return allCards.filter { $0.deck?.id == filterDeckID }
    }

    var body: some View {
        NavigationStack {
            Group {
                if allCards.isEmpty && decks.allSatisfy({ $0.cardCount == 0 }) {
                    emptyLibraryState
                } else if groupedEntries.isEmpty {
                    ContentUnavailableView {
                        Label(L10n.libraryNoResultsTitle, systemImage: "magnifyingglass")
                    } description: {
                        Text(L10n.libraryNoResultsMessage)
                    }
                } else {
                    List {
                        if let filterDeckID, let deck = decks.first(where: { $0.id == filterDeckID }) {
                            Section {
                                let dueCards = deck.cards.filter { ReviewScheduler.isDue($0) }
                                if !dueCards.isEmpty {
                                    NavigationLink {
                                        CardReviewSessionView(cards: dueCards, dismissWhenComplete: true)
                                            .navigationTitle(deck.name)
                                            .navigationBarTitleDisplayMode(.inline)
                                    } label: {
                                        Label(L10n.libraryReviewDeck(deck.name, count: dueCards.count), systemImage: "brain.head.profile")
                                    }
                                }
                            }
                        }

                        ForEach(groupedEntries, id: \.word) { entry in
                            Section {
                                ForEach(entry.cards) { card in
                                    NavigationLink {
                                        FlashCardDetailView(card: card)
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        DeckStoreView(selectedDeckID: Binding(
                            get: { filterDeckID ?? selectedDeckID },
                            set: { newValue in
                                filterDeckID = newValue
                                selectedDeckID = newValue
                                if let newValue {
                                    DeckSettings.lastSelectedDeckID = newValue
                                }
                            }
                        ))
                    } label: {
                        Image(systemName: "books.vertical")
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                deckFilterBar
            }
            .onAppear {
                DeckService.bootstrap(in: modelContext)
                if filterDeckID == nil {
                    filterDeckID = DeckSettings.lastSelectedDeckID
                }
            }
        }
    }

    private var emptyLibraryState: some View {
        ContentUnavailableView {
            Label(L10n.libraryEmptyTitle, systemImage: "tray")
        } description: {
            Text(L10n.libraryEmptyMessage)
        } actions: {
            NavigationLink {
                DeckStoreView(selectedDeckID: $selectedDeckID)
            } label: {
                Text(L10n.deckBrowsePresets)
            }
        }
    }

    @ViewBuilder
    private var deckFilterBar: some View {
        if !decks.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    deckChip(title: L10n.deckFilterAll, deckID: nil, count: allCards.count)

                    ForEach(decks) { deck in
                        deckChip(title: deck.name, deckID: deck.id, count: deck.cardCount)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .background(.bar)
        }
    }

    private func deckChip(title: String, deckID: UUID?, count: Int) -> some View {
        let isSelected = filterDeckID == deckID
        return Button {
            filterDeckID = deckID
            if let deckID {
                DeckSettings.lastSelectedDeckID = deckID
            }
        } label: {
            Text(count > 0 ? L10n.deckLabelWithCount(title, count: count) : title)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
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

                if let deckName = card.deck?.name, filterDeckID == nil {
                    Text(deckName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

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
                || (card.deck?.name.localizedCaseInsensitiveContains(query) ?? false)
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
        .modelContainer(for: [Deck.self, FlashCard.self], inMemory: true)
}

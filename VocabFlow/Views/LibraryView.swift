import SwiftUI
import SwiftData

struct LibraryView: View {
    @Query(sort: [SortDescriptor(\Deck.sortOrder), SortDescriptor(\Deck.createdAt)])
    private var decks: [Deck]

    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var filterDeckID: UUID?
    @State private var selectedDeckID: UUID?
    @State private var totalCardCount = 0
    @State private var deckCounts: [UUID: Int] = [:]
    @State private var catalogLoaded = false
    @State private var searchDebounceTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Group {
                if catalogLoaded && totalCardCount == 0 {
                    emptyLibraryState
                } else {
                    LibraryGroupedList(
                        filterDeckID: filterDeckID,
                        searchText: debouncedSearchText,
                        decks: decks,
                        onCardsDeleted: {
                            Task { await refreshCatalogCounts() }
                        }
                    )
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
                if filterDeckID == nil {
                    filterDeckID = DeckSettings.lastSelectedDeckID
                }
            }
            .task {
                await refreshCatalogCounts()
            }
            .onChange(of: searchText) { _, newValue in
                searchDebounceTask?.cancel()
                searchDebounceTask = Task {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled else { return }
                    debouncedSearchText = newValue
                }
            }
        }
    }

    @MainActor
    private func refreshCatalogCounts() async {
        await Task.yield()
        let descriptor = FetchDescriptor<FlashCard>()
        guard let cards = try? modelContext.fetch(descriptor) else { return }

        let snapshots = LibraryCardGrouper.makeSnapshots(from: cards)
        totalCardCount = snapshots.count
        deckCounts = await Task.detached(priority: .utility) {
            LibraryCardGrouper.deckCounts(from: snapshots)
        }.value
        catalogLoaded = true
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
                Text(L10n.deckManage)
            }
        }
    }

    @ViewBuilder
    private var deckFilterBar: some View {
        if !decks.isEmpty {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        deckChip(title: L10n.deckFilterAll, deckID: nil, count: totalCardCount)
                            .id(LibraryDeckChipID.all)

                        ForEach(decks) { deck in
                            deckChip(
                                title: deck.name,
                                deckID: deck.id,
                                count: deckCounts[deck.id, default: 0]
                            )
                            .id(LibraryDeckChipID.deck(deck.id))
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .background(.bar)
                .onAppear {
                    scrollFilterBar(to: filterDeckID, using: proxy, animated: false)
                }
                .onChange(of: filterDeckID) { _, deckID in
                    scrollFilterBar(to: deckID, using: proxy, animated: false)
                }
            }
        }
    }

    private func scrollFilterBar(
        to deckID: UUID?,
        using proxy: ScrollViewProxy,
        animated: Bool
    ) {
        let target = LibraryDeckChipID(deckID: deckID)
        if animated {
            proxy.scrollTo(target, anchor: .center)
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                proxy.scrollTo(target, anchor: .center)
            }
        }
    }

    private func deckChip(title: String, deckID: UUID?, count: Int) -> some View {
        let isSelected = filterDeckID == deckID
        return Button {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                filterDeckID = deckID
            }
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
}

private enum LibraryDeckChipID: Hashable {
    case all
    case deck(UUID)

    init(deckID: UUID?) {
        if let deckID {
            self = .deck(deckID)
        } else {
            self = .all
        }
    }
}

private struct LibraryGroupedList: View {
    let filterDeckID: UUID?
    let searchText: String
    let decks: [Deck]
    let onCardsDeleted: () -> Void

    @Environment(\.modelContext) private var modelContext

    @State private var cards: [FlashCard] = []
    @State private var groups: [LibraryWordGroup] = []
    @State private var cardsByID: [UUID: FlashCard] = [:]
    @State private var dueCards: [FlashCard] = []
    @State private var visibleGroupCount = LibraryCardGrouper.groupPageSize
    @State private var isLoadingGroups = false

    private var refreshToken: String {
        "\(filterDeckID?.uuidString ?? "all")|\(searchText)"
    }

    var body: some View {
        Group {
            if isLoadingGroups && groups.isEmpty {
                ProgressView(L10n.deckLoading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if groups.isEmpty {
                ContentUnavailableView {
                    Label(L10n.libraryNoResultsTitle, systemImage: "magnifyingglass")
                } description: {
                    Text(L10n.libraryNoResultsMessage)
                }
            } else {
                List {
                    if let filterDeckID, let deck = decks.first(where: { $0.id == filterDeckID }), !dueCards.isEmpty {
                        Section {
                            NavigationLink {
                                CardReviewSessionView(cards: dueCards, dismissWhenComplete: true)
                                    .navigationTitle(deck.name)
                                    .navigationBarTitleDisplayMode(.inline)
                            } label: {
                                Label(L10n.libraryReviewDeck(deck.name, count: dueCards.count), systemImage: "brain.head.profile")
                            }
                        }
                    }

                    ForEach(groups.prefix(visibleGroupCount)) { group in
                        Section {
                            ForEach(group.cardIDs, id: \.self) { cardID in
                                if let card = cardsByID[cardID] {
                                    NavigationLink {
                                        FlashCardDetailView(card: card)
                                    } label: {
                                        LibraryCardRow(card: card, showsDeckName: filterDeckID == nil)
                                    }
                                }
                            }
                            .onDelete { offsets in
                                deleteCards(in: group, at: offsets)
                            }

                            if group.cardIDs.count > 1,
                               let reviewCards = resolvedCards(for: group.cardIDs) {
                                NavigationLink {
                                    CardReviewSessionView(cards: reviewCards, dismissWhenComplete: true)
                                        .navigationTitle(group.word)
                                        .navigationBarTitleDisplayMode(.inline)
                                } label: {
                                    Label(
                                        L10n.reviewAll(group.word, count: group.cardIDs.count),
                                        systemImage: "brain.head.profile"
                                    )
                                    .font(.subheadline)
                                }
                            }
                        } header: {
                            Text(group.word)
                        }
                    }

                    if visibleGroupCount < groups.count {
                        Section {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                            .task {
                                visibleGroupCount = min(
                                    visibleGroupCount + LibraryCardGrouper.groupPageSize,
                                    groups.count
                                )
                            }
                        }
                    }
                }
                .animation(.none, value: filterDeckID)
                .overlay(alignment: .top) {
                    if isLoadingGroups {
                        ProgressView()
                            .padding(8)
                            .background(.bar, in: Capsule())
                            .padding(.top, 8)
                    }
                }
            }
        }
        .task(id: refreshToken) {
            await rebuildGroups()
        }
    }

    @MainActor
    private func rebuildGroups() async {
        isLoadingGroups = true
        visibleGroupCount = LibraryCardGrouper.groupPageSize
        defer { isLoadingGroups = false }

        await Task.yield()
        try? await Task.sleep(for: .milliseconds(32))

        let fetchedCards = fetchCards(for: filterDeckID)
        cards = fetchedCards

        let snapshots = LibraryCardGrouper.makeSnapshots(from: fetchedCards)
        let cardLookup = Dictionary(uniqueKeysWithValues: fetchedCards.map { ($0.id, $0) })
        let query = searchText

        let grouped = await Task.detached(priority: .userInitiated) {
            LibraryCardGrouper.group(snapshots: snapshots, searchQuery: query)
        }.value

        let due = snapshots.filter(\.isDue).compactMap { cardLookup[$0.id] }

        cardsByID = cardLookup
        groups = grouped
        dueCards = due
    }

    private func fetchCards(for deckID: UUID?) -> [FlashCard] {
        if let deckID {
            let id = deckID
            var descriptor = FetchDescriptor<FlashCard>(
                predicate: #Predicate<FlashCard> { card in
                    card.deck?.id == id
                },
                sortBy: [SortDescriptor(\FlashCard.createdAt, order: .reverse)]
            )
            return (try? modelContext.fetch(descriptor)) ?? []
        }

        let descriptor = FetchDescriptor<FlashCard>(
            sortBy: [SortDescriptor(\FlashCard.createdAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func resolvedCards(for ids: [UUID]) -> [FlashCard]? {
        let resolved = ids.compactMap { cardsByID[$0] }
        return resolved.count == ids.count ? resolved : nil
    }

    private func deleteCards(in group: LibraryWordGroup, at offsets: IndexSet) {
        offsets
            .compactMap { group.cardIDs[$0] }
            .compactMap { cardsByID[$0] }
            .forEach { modelContext.delete($0) }
        onCardsDeleted()
    }
}

private struct LibraryCardRow: View {
    let card: FlashCard
    let showsDeckName: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(card.cardType.displayName)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.blue.opacity(0.12))
                    .clipShape(Capsule())

                if let deckName = card.deck?.name, showsDeckName {
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
}

#Preview {
    LibraryView()
        .modelContainer(for: [Deck.self, FlashCard.self], inMemory: true)
}

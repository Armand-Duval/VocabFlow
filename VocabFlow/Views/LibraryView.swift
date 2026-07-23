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
    @State private var hasAnyCards = true
    @State private var forceGrouped = false
    @State private var searchDebounceTask: Task<Void, Never>?

    private var totalCardCount: Int {
        LibraryCatalogCache.shared.totalCount(from: decks)
    }

    private var deckCounts: [UUID: Int] {
        LibraryCatalogCache.shared.deckCounts(from: decks)
    }

    var body: some View {
        NavigationStack {
            Group {
                if !hasAnyCards {
                    emptyLibraryState
                } else {
                    LibraryGroupedList(
                        filterDeckID: filterDeckID,
                        searchText: debouncedSearchText,
                        decks: decks,
                        forceGrouped: forceGrouped,
                        onCardsDeleted: {
                            LibraryCatalogCache.shared.invalidateListCache()
                            DeckCardCountService.notifyCatalogChanged()
                            Task { await refreshHasAnyCards() }
                        }
                    )
                }
            }
            .navigationTitle(L10n.libraryTitle)
            .searchable(text: $searchText, prompt: L10n.librarySearchPrompt)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        if totalCardCount >= LibraryCardGrouper.flatListThreshold {
                            Button {
                                forceGrouped.toggle()
                            } label: {
                                Image(systemName: forceGrouped ? "rectangle.grid.1x2" : "list.bullet")
                            }
                            .accessibilityLabel(
                                forceGrouped ? L10n.libraryViewFlat : L10n.libraryViewGrouped
                            )
                        }

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
                await refreshHasAnyCards()
            }
            .onReceive(NotificationCenter.default.publisher(for: .libraryCatalogDidChange)) { _ in
                LibraryCatalogCache.shared.invalidateListCache()
                Task { await refreshHasAnyCards() }
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
    private func refreshHasAnyCards() async {
        await Task.yield()
        var descriptor = FetchDescriptor<FlashCard>()
        descriptor.fetchLimit = 1
        hasAnyCards = !((try? modelContext.fetch(descriptor)) ?? []).isEmpty
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
                            HStack(spacing: 4) {
                                deckChip(
                                    title: deck.name,
                                    deckID: deck.id,
                                    count: deckCounts[deck.id, default: 0]
                                )

                                NavigationLink {
                                    DeckStatisticsView(deck: deck)
                                } label: {
                                    Image(systemName: "chart.bar.xaxis")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
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
    let forceGrouped: Bool
    let onCardsDeleted: () -> Void

    @Environment(\.modelContext) private var modelContext

    @State private var cards: [FlashCard] = []
    @State private var groups: [LibraryWordGroup] = []
    @State private var flatCardIDs: [UUID] = []
    @State private var useFlatList = false
    @State private var cardsByID: [UUID: FlashCard] = [:]
    @State private var dueCards: [FlashCard] = []
    @State private var visibleItemCount = LibraryCardGrouper.groupPageSize
    @State private var isLoadingGroups = false

    private var refreshToken: String {
        "\(filterDeckID?.uuidString ?? "all")|\(searchText)|\(forceGrouped)"
    }

    var body: some View {
        Group {
            if isLoadingGroups && groups.isEmpty && flatCardIDs.isEmpty {
                ProgressView(L10n.deckLoading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if groups.isEmpty && flatCardIDs.isEmpty {
                ContentUnavailableView {
                    Label(L10n.libraryNoResultsTitle, systemImage: "magnifyingglass")
                } description: {
                    Text(L10n.libraryNoResultsMessage)
                }
            } else {
                List {
                    if useFlatList {
                        Section {
                            Text(L10n.libraryFlatListHint)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        ForEach(flatCardIDs.prefix(visibleItemCount), id: \.self) { cardID in
                            if let card = cardsByID[cardID] {
                                NavigationLink {
                                    FlashCardDetailView(card: card)
                                } label: {
                                    LibraryCardRow(card: card, showsDeckName: filterDeckID == nil)
                                }
                            }
                        }
                        .onDelete { offsets in
                            deleteFlatCards(at: offsets)
                        }
                    } else {
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

                        ForEach(groups.prefix(visibleItemCount)) { group in
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
                    }

                    if visibleItemCount < currentTotalItems {
                        Section {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                            .task {
                                visibleItemCount = min(
                                    visibleItemCount + LibraryCardGrouper.groupPageSize,
                                    currentTotalItems
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

    private var currentTotalItems: Int {
        useFlatList ? flatCardIDs.count : groups.count
    }

    @MainActor
    private func rebuildGroups() async {
        isLoadingGroups = true
        visibleItemCount = LibraryCardGrouper.groupPageSize
        defer { isLoadingGroups = false }

        await Task.yield()
        try? await Task.sleep(for: .milliseconds(16))

        let fetchedCards = fetchCards(for: filterDeckID)
        cards = fetchedCards

        let cache = LibraryCatalogCache.shared
        let cacheKey = cache.cacheKey(
            filterDeckID: filterDeckID,
            search: searchText,
            cardCount: fetchedCards.count
        )

        let cardLookup = Dictionary(uniqueKeysWithValues: fetchedCards.map { ($0.id, $0) })
        let snapshots = LibraryCardGrouper.makeSnapshots(from: fetchedCards)
        let query = searchText

        let listData: (groups: [LibraryWordGroup], flatCardIDs: [UUID], useFlatList: Bool, searchIndex: LibrarySearchIndex)
        if let cached = cache.cachedList(for: cacheKey), !forceGrouped {
            groups = cached.groups
            flatCardIDs = cached.flatCardIDs
            useFlatList = cached.useFlatList
            dueCards = cached.dueCardIDs.compactMap { cardLookup[$0] }
        } else {
            let built = await Task.detached(priority: .userInitiated) {
                LibraryCardGrouper.buildListData(snapshots: snapshots, searchQuery: query)
            }.value

            var shouldUseFlat = built.useFlatList && !forceGrouped
            groups = shouldUseFlat ? [] : built.groups
            flatCardIDs = shouldUseFlat ? built.flatCardIDs : []
            useFlatList = shouldUseFlat

            let due = snapshots.filter(\.isDue).compactMap { cardLookup[$0.id] }
            dueCards = due

            cache.store(
                LibraryListCacheEntry(
                    groups: groups,
                    flatCardIDs: flatCardIDs,
                    dueCardIDs: due.map(\.id),
                    useFlatList: useFlatList
                ),
                for: cacheKey
            )
        }

        cardsByID = cardLookup
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
        let deleted = offsets
            .compactMap { group.cardIDs[$0] }
            .compactMap { cardsByID[$0] }
        deleted.forEach { card in
            if let deck = card.deck {
                DeckCardCountService.adjust(deck: deck, by: -1, in: modelContext)
            }
            modelContext.delete(card)
        }
        onCardsDeleted()
    }

    private func deleteFlatCards(at offsets: IndexSet) {
        let ids = offsets.compactMap { flatCardIDs[safe: $0] }
        ids.compactMap { cardsByID[$0] }.forEach { card in
            if let deck = card.deck {
                DeckCardCountService.adjust(deck: deck, by: -1, in: modelContext)
            }
            modelContext.delete(card)
        }
        onCardsDeleted()
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
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

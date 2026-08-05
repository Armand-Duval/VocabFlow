import SwiftUI
import SwiftData

private enum LibraryCardFilter: String, CaseIterable, Identifiable {
    case all
    case due
    case definition
    case cloze

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: L10n.libraryFilterAll
        case .due: L10n.libraryFilterDue
        case .definition: L10n.libraryFilterDefinition
        case .cloze: L10n.libraryFilterCloze
        }
    }
}

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
    @State private var cardFilter: LibraryCardFilter = .all
    @State private var showCardFilterSheet = false
    @State private var showDeckStore = false
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var autoBackupBannerText: String?

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
                        cardFilter: cardFilter,
                        decks: decks,
                        forceGrouped: forceGrouped,
                        onCardsDeleted: {
                            LibraryCatalogCache.shared.invalidateListCache()
                            DeckCardCountService.notifyCatalogChanged()
                            SharedDedupeSync.rebuild(in: modelContext)
                            Task { await refreshHasAnyCards() }
                        }
                    )
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: L10n.librarySearchPrompt)
            .appPageBackground()
            .appNavTitle(L10n.libraryTitle, style: .hidden)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ToolbarIconCluster {
                        if hasAnyCards {
                            cardFilterMenu
                        }

                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                                debouncedSearchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(AppColor.textTertiary)
                            }
                            .buttonStyle(SoftPressButtonStyle())
                            .accessibilityLabel(L10n.clear)
                        }

                        if totalCardCount >= LibraryCardGrouper.flatListThreshold {
                            Button {
                                forceGrouped.toggle()
                            } label: {
                                AppIcon.symbol(forceGrouped ? "rectangle.grid.1x2" : "list.bullet")
                            }
                            .buttonStyle(SoftPressButtonStyle())
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
                            AppIcon.symbol("books.vertical")
                        }
                        .buttonStyle(SoftPressButtonStyle())

                        Button {
                            AppTab.requestSettings()
                        } label: {
                            AppIcon.symbol("gearshape")
                        }
                        .buttonStyle(SoftPressButtonStyle())
                        .accessibilityLabel(L10n.settingsTitle)
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    if let autoBackupBannerText {
                        autoBackupBanner(autoBackupBannerText)
                    }
                    deckFilterBar
                }
            }
            .navigationDestination(isPresented: $showDeckStore) {
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
            }
            .onAppear {
                if filterDeckID == nil {
                    filterDeckID = DeckSettings.lastSelectedDeckID
                }
                refreshAutoBackupBanner()
            }
            .task {
                await refreshHasAnyCards()
            }
            .onReceive(NotificationCenter.default.publisher(for: .libraryCatalogDidChange)) { _ in
                LibraryCatalogCache.shared.invalidateListCache()
                Task { await refreshHasAnyCards() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .dailyAutoBackupBannerDidChange)) { _ in
                refreshAutoBackupBanner()
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

    private func refreshAutoBackupBanner() {
        autoBackupBannerText = DailyAutoBackupService.pendingBannerText
    }

    private func autoBackupBanner(_ message: String) -> some View {
        HStack(alignment: .center, spacing: AppSpacing.sm) {
            Button {
                _ = DailyAutoBackupService.openAutoBackupInFiles()
            } label: {
                HStack(alignment: .center, spacing: AppSpacing.sm) {
                    Image(systemName: "externaldrive.badge.checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppColor.accent)
                    Text(message)
                        .font(AppFont.helper())
                        .foregroundStyle(AppColor.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColor.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(L10n.libraryAutoBackupBannerOpenHint)

            Button {
                DailyAutoBackupService.dismissBanner()
                refreshAutoBackupBanner()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColor.textTertiary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.close)
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.accentBackground(0.14))
    }

    @MainActor
    private func refreshHasAnyCards() async {
        await Task.yield()
        var descriptor = FetchDescriptor<FlashCard>()
        descriptor.fetchLimit = 1
        hasAnyCards = !((try? modelContext.fetch(descriptor)) ?? []).isEmpty
    }

    private var emptyLibraryState: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer()
            AppEmptyState(
                title: L10n.libraryEmptyTitle,
                message: L10n.libraryEmptyGoCreate,
                systemImage: "books.vertical"
            )
            NavigationLink {
                DeckStoreView(selectedDeckID: $selectedDeckID)
            } label: {
                Text(L10n.deckManage)
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, AppSpacing.xl)
            Spacer()
        }
    }

    @ViewBuilder
    private var cardFilterMenu: some View {
        Button {
            showCardFilterSheet = true
        } label: {
            AppIcon.symbol(cardFilter == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
        .buttonStyle(SoftPressButtonStyle())
        .accessibilityLabel(L10n.libraryFilterMenu)
        .appSelectionSheet(
            isPresented: $showCardFilterSheet,
            title: L10n.libraryFilterMenu,
            options: LibraryCardFilter.allCases.map {
                AppSelectionOption(id: $0.rawValue, title: $0.title)
            },
            selectedID: cardFilter.rawValue
        ) { selectedID in
            if let filter = LibraryCardFilter(rawValue: selectedID) {
                cardFilter = filter
            }
        }
    }

    @ViewBuilder
    private var deckFilterBar: some View {
        if !decks.isEmpty {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.sm) {
                        deckChip(title: L10n.deckFilterAll, deckID: nil, count: totalCardCount)
                            .id(LibraryDeckChipID.all)

                        ForEach(decks) { deck in
                            HStack(spacing: 6) {
                                deckChip(
                                    title: deck.name,
                                    deckID: deck.id,
                                    count: deckCounts[deck.id, default: 0]
                                )

                                NavigationLink {
                                    DeckStatisticsView(deck: deck)
                                } label: {
                                    AppIcon.symbol("chart.bar.xaxis")
                                        .font(.caption2)
                                        .foregroundStyle(AppColor.textTertiary.opacity(0.38))
                                }
                                .buttonStyle(SoftPressButtonStyle())
                            }
                            .id(LibraryDeckChipID.deck(deck.id))
                        }
                    }
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.top, AppSpacing.xs)
                    .padding(.bottom, AppSpacing.sm)
                }
                .background(AppColor.pageBackground)
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
        DeckFilterChip(
            title: title,
            badge: count > 0 ? count : nil,
            isSelected: filterDeckID == deckID,
            action: {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    filterDeckID = deckID
                }
                // Shared current deck: nil = all decks (Review / badge use the same value).
                DeckSettings.lastSelectedDeckID = deckID
            }
        )
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
    let cardFilter: LibraryCardFilter
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
        "\(filterDeckID?.uuidString ?? "all")|\(searchText)|\(forceGrouped)|\(cardFilter.rawValue)"
    }

    var body: some View {
        Group {
            if isLoadingGroups && groups.isEmpty && flatCardIDs.isEmpty {
                ProgressView {
                    Text(L10n.deckLoading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if groups.isEmpty && flatCardIDs.isEmpty {
                AppEmptyState(
                    title: L10n.libraryNoResultsTitle,
                    message: L10n.libraryNoResultsMessage,
                    systemImage: "magnifyingglass"
                )
            } else {
                libraryList
            }
        }
        .task(id: refreshToken) {
            await rebuildGroups()
        }
    }

    private var libraryList: some View {
        List {
            if useFlatList {
                flatListContent
            } else {
                groupedListContent
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
        .listSectionSpacing(AppSpacing.md)
        .appListSurface()
        .animation(.none, value: filterDeckID)
        .overlay(alignment: .top) {
            if isLoadingGroups {
                ProgressView()
                    .tint(AppColor.accent)
                    .padding(8)
                    .background(AppColor.surface, in: Capsule())
                    .padding(.top, 8)
            }
        }
    }

    @ViewBuilder
    private var flatListContent: some View {
        Section {
            Text(L10n.libraryFlatListHint)
                .font(AppFont.caption())
                .foregroundStyle(.secondary)
        }

                ForEach(flatCardIDs.prefix(visibleItemCount), id: \.self) { cardID in
            if let card = cardsByID[cardID] {
                NavigationLink {
                    FlashCardDetailView(card: card)
                } label: {
                    LibraryCardRow(
                        card: card,
                        showsDeckName: filterDeckID == nil,
                        searchHighlight: searchText
                    )
                }
                .buttonStyle(SoftPressButtonStyle(pressedScale: 0.99, pressedOpacity: 0.92))
            }
        }
        .onDelete { offsets in
            deleteFlatCards(at: offsets)
        }
    }

    @ViewBuilder
    private var groupedListContent: some View {
        if let filterDeckID, let deck = decks.first(where: { $0.id == filterDeckID }), !dueCards.isEmpty {
            Section {
                NavigationLink {
                    CardReviewSessionView(cards: dueCards, dismissWhenComplete: true)
                } label: {
                    Label {
                        Text(L10n.libraryReviewDeck(deck.name, count: dueCards.count))
                            .font(AppFont.secondary().weight(.semibold))
                            .foregroundStyle(AppColor.accentStrong)
                    } icon: {
                        Image(systemName: "brain.head.profile")
                            .foregroundStyle(AppColor.accentStrong)
                            .symbolRenderingMode(.monochrome)
                    }
                }
                .buttonStyle(SoftPressButtonStyle(pressedScale: 0.99, pressedOpacity: 0.9))
                .tint(AppColor.accentStrong)
            }
        }

        ForEach(groups.prefix(visibleItemCount)) { group in
            Section {
                ForEach(group.cardIDs, id: \.self) { cardID in
                    if let card = cardsByID[cardID] {
                        NavigationLink {
                            FlashCardDetailView(card: card)
                        } label: {
                            LibraryCardRow(
                                card: card,
                                showsDeckName: filterDeckID == nil,
                                searchHighlight: searchText
                            )
                        }
                        .buttonStyle(SoftPressButtonStyle(pressedScale: 0.99, pressedOpacity: 0.92))
                    }
                }
                .onDelete { offsets in
                    deleteCards(in: group, at: offsets)
                }

                if group.cardIDs.count > 1,
                   let reviewCards = resolvedCards(for: group.cardIDs) {
                    NavigationLink {
                        CardReviewSessionView(cards: reviewCards, dismissWhenComplete: true)
                    } label: {
                        Label {
                            Text(L10n.reviewAll(group.word, count: group.cardIDs.count))
                                .font(AppFont.secondary().weight(.semibold))
                                .foregroundStyle(AppColor.accentStrong)
                        } icon: {
                            Image(systemName: "brain.head.profile")
                                .foregroundStyle(AppColor.accentStrong)
                                .symbolRenderingMode(.monochrome)
                        }
                    }
                    .buttonStyle(SoftPressButtonStyle(pressedScale: 0.99, pressedOpacity: 0.9))
                    .tint(AppColor.accentStrong)
                }
            } header: {
                AppSectionHeader(title: group.word)
            }
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

        let fetchedCards = fetchCards(for: filterDeckID, filter: cardFilter)
        cards = fetchedCards

        let cache = LibraryCatalogCache.shared
        let cacheKey = cache.cacheKey(
            filterDeckID: filterDeckID,
            search: searchText,
            cardCount: fetchedCards.count,
            cardFilter: cardFilter.rawValue,
            forceGrouped: forceGrouped
        )

        let cardLookup = Dictionary(uniqueKeysWithValues: fetchedCards.map { ($0.id, $0) })
        let snapshots = LibraryCardGrouper.makeSnapshots(from: fetchedCards)
        let query = searchText

        if let cached = cache.cachedList(for: cacheKey),
           !forceGrouped,
           cacheEntryResolves(cached, in: cardLookup) {
            groups = cached.groups
            flatCardIDs = cached.flatCardIDs
            useFlatList = cached.useFlatList
            dueCards = cached.dueCardIDs.compactMap { cardLookup[$0] }
        } else {
            let built = await Task.detached(priority: .userInitiated) {
                LibraryCardGrouper.buildListData(snapshots: snapshots, searchQuery: query)
            }.value

            let shouldUseFlat = built.useFlatList && !forceGrouped
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

    private func cacheEntryResolves(_ entry: LibraryListCacheEntry, in lookup: [UUID: FlashCard]) -> Bool {
        if entry.useFlatList {
            return !entry.flatCardIDs.isEmpty && entry.flatCardIDs.allSatisfy { lookup[$0] != nil }
        }
        return entry.groups.allSatisfy { group in
            !group.cardIDs.isEmpty && group.cardIDs.allSatisfy { lookup[$0] != nil }
        }
    }

    private func fetchCards(for deckID: UUID?, filter: LibraryCardFilter) -> [FlashCard] {
        let baseCards: [FlashCard]
        if let deckID {
            let id = deckID
            var descriptor = FetchDescriptor<FlashCard>(
                predicate: #Predicate<FlashCard> { card in
                    card.deck?.id == id
                },
                sortBy: [SortDescriptor(\FlashCard.createdAt, order: .reverse)]
            )
            baseCards = (try? modelContext.fetch(descriptor)) ?? []
        } else {
            let descriptor = FetchDescriptor<FlashCard>(
                sortBy: [SortDescriptor(\FlashCard.createdAt, order: .reverse)]
            )
            baseCards = (try? modelContext.fetch(descriptor)) ?? []
        }

        switch filter {
        case .all:
            return baseCards
        case .due:
            return baseCards.filter { ReviewScheduler.isDue($0) }
        case .definition:
            return baseCards.filter { $0.cardType == .definition }
        case .cloze:
            return baseCards.filter { $0.cardType == .cloze }
        }
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
    var searchHighlight: String = ""

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.sm) {
            VStack(alignment: .leading, spacing: 4) {
                HighlightedText(
                    text: card.word,
                    query: searchHighlight,
                    font: .body.weight(.semibold),
                    lineLimit: 1,
                    matchStyle: .substring
                )
                .foregroundStyle(AppColor.textPrimary)

                if !contextLine.isEmpty {
                    HighlightedText(
                        text: contextLine,
                        query: searchHighlight,
                        font: AppFont.caption(),
                        lineLimit: 1,
                        matchStyle: .substring
                    )
                    .foregroundStyle(AppColor.textTertiary)
                } else if showsDeckName, let deckName = card.deck?.name {
                    Text(deckName)
                        .font(AppFont.helper())
                        .foregroundStyle(AppColor.textMuted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: AppSpacing.sm)

            VStack(alignment: .trailing, spacing: 4) {
                Text(card.cardType.displayName)
                    .font(AppFont.weak())
                    .foregroundStyle(AppColor.textMuted)
                LibraryCardStatusChip(card: card)
            }
        }
        .padding(.vertical, 4)
        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        .listRowSeparatorTint(AppColor.borderSubtle)
    }

    private var contextLine: String {
        // Cloze: prefer the blanked front so filter results are recognizable.
        if card.cardType == .cloze {
            let trimmedFront = card.front.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedFront.isEmpty {
                return trimmedFront
            }
        }

        let trimmedSentence = card.sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSentence.isEmpty {
            return trimmedSentence
        }

        let trimmedFront = card.front.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedWord = card.word.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedFront.isEmpty, trimmedFront.caseInsensitiveCompare(trimmedWord) != .orderedSame {
            return trimmedFront
        }

        return card.displayBack
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

#Preview {
    LibraryView()
        .modelContainer(for: [Deck.self, FlashCard.self], inMemory: true)
}

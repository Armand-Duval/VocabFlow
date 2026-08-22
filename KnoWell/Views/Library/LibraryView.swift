import SwiftUI
import SwiftData

private enum LibraryCardFilter: String, CaseIterable, Identifiable {
    case all
    case due
    case definition
    case cloze
    case appreciation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: L10n.libraryFilterAll
        case .due: L10n.libraryFilterDue
        case .definition: L10n.libraryFilterDefinition
        case .cloze: L10n.libraryFilterCloze
        case .appreciation: L10n.libraryFilterAppreciation
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
    @State private var listRevision = 0
    @State private var isSelecting = false
    @State private var selectedCardIDs: Set<UUID> = []
    @State private var listedCardIDs: [UUID] = []
    @State private var showMigrateSheet = false
    @State private var migrateToDeckID: UUID?

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
                        catalogRevision: listRevision,
                        isSelecting: isSelecting,
                        selectedCardIDs: $selectedCardIDs,
                        listedCardIDs: $listedCardIDs,
                        migrateToDeckID: $migrateToDeckID,
                        onCardsDeleted: {
                            handleLibraryMutation()
                        }
                    )
                }
            }
            .appPageBackground()
            .appNavTitle(L10n.libraryTitle, style: .hidden)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    if let autoBackupBannerText {
                        autoBackupBanner(autoBackupBannerText)
                    }
                    libraryChromeRow
                    deckFilterBar
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isSelecting, hasAnyCards {
                    selectionToolbar
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
                listRevision += 1
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
            .onChange(of: filterDeckID) { _, _ in
                selectedCardIDs = []
            }
            .onChange(of: isSelecting) { _, selecting in
                if !selecting {
                    selectedCardIDs = []
                    showMigrateSheet = false
                }
            }
            .appSelectionSheet(
                isPresented: $showMigrateSheet,
                title: L10n.libraryMigrateTitle,
                options: decks.map { AppSelectionOption(id: $0.id, title: $0.name) },
                selectedID: filterDeckID
            ) { deckID in
                migrateToDeckID = deckID
            }
        }
    }

    /// Search + filter + library tools on one quiet row.
    private var libraryChromeRow: some View {
        HStack(spacing: AppSpacing.sm) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColor.textMuted)

                TextField(L10n.librarySearchPrompt, text: $searchText)
                    .font(AppFont.secondary())
                    .foregroundStyle(AppColor.textPrimary)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        debouncedSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(AppColor.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.clear)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(AppColor.surface, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(AppColor.borderSubtle, lineWidth: 1)
            }
            .appSoftShadow()

            if hasAnyCards {
                cardFilterMenu

                Button {
                    isSelecting.toggle()
                } label: {
                    AppIcon.symbol(isSelecting ? "checkmark.circle.fill" : "checkmark.circle")
                }
                .buttonStyle(SoftPressButtonStyle())
                .accessibilityLabel(isSelecting ? L10n.librarySelectDone : L10n.librarySelect)
            }

            Button {
                showDeckStore = true
            } label: {
                AppIcon.symbol("books.vertical")
            }
            .buttonStyle(SoftPressButtonStyle())
            .accessibilityLabel(L10n.deckManage)

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
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.top, AppSpacing.xs)
        .padding(.bottom, 6)
        .background(AppColor.pageBackground)
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
        if !hasAnyCards {
            isSelecting = false
            selectedCardIDs = []
        }
    }

    private func handleLibraryMutation() {
        LibraryCatalogCache.shared.invalidateListCache()
        DeckCardCountService.notifyCatalogChanged()
        SharedDedupeSync.rebuild(in: modelContext)
        Task { await refreshHasAnyCards() }
    }

    private var selectionToolbar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(AppColor.borderSubtle)
                .frame(height: 1)

            HStack(spacing: AppSpacing.sm) {
                Button {
                    if selectedCardIDs.count == listedCardIDs.count, !listedCardIDs.isEmpty {
                        selectedCardIDs = []
                    } else {
                        selectedCardIDs = Set(listedCardIDs)
                    }
                } label: {
                    Text(
                        selectedCardIDs.count == listedCardIDs.count && !listedCardIDs.isEmpty
                            ? L10n.deckDeselectAll
                            : L10n.deckSelectAll
                    )
                    .font(AppFont.helper().weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColor.accent)
                .disabled(listedCardIDs.isEmpty)

                Text(L10n.librarySelectedCount(selectedCardIDs.count))
                    .font(AppFont.helper())
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    showMigrateSheet = true
                } label: {
                    Text(L10n.libraryMigrate)
                        .font(AppFont.helper().weight(.semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(AppColor.accentStrong, in: Capsule())
                }
                .buttonStyle(SoftPressButtonStyle())
                .disabled(selectedCardIDs.isEmpty)
                .opacity(selectedCardIDs.isEmpty ? 0.45 : 1)
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, 10)
            .background(AppColor.pageBackground)
        }
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
                    HStack(spacing: 6) {
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
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.top, 4)
                    .padding(.bottom, AppSpacing.xs)
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
                if let deckID {
                    DeckSettings.lastSelectedDeckID = deckID
                }
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
    let catalogRevision: Int
    let isSelecting: Bool
    @Binding var selectedCardIDs: Set<UUID>
    @Binding var listedCardIDs: [UUID]
    @Binding var migrateToDeckID: UUID?
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
    @State private var lastGroupingToken = ""

    private var groupingToken: String {
        "\(filterDeckID?.uuidString ?? "all")|\(searchText)|\(forceGrouped)|\(cardFilter.rawValue)"
    }

    private var refreshToken: String {
        "\(groupingToken)|\(catalogRevision)"
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
        .onChange(of: migrateToDeckID) { _, deckID in
            guard let deckID else { return }
            migrateToDeckID = nil
            migrateSelected(to: deckID)
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
            ForEach(flatCardIDs.prefix(visibleItemCount), id: \.self) { cardID in
                if let card = cardsByID[cardID] {
                    cardRow(card: card, cardID: cardID)
                }
            }
            .onDelete(perform: isSelecting ? nil : deleteFlatCards)
        }
    }

    @ViewBuilder
    private var groupedListContent: some View {
        if let filterDeckID, let deck = decks.first(where: { $0.id == filterDeckID }), !dueCards.isEmpty, !isSelecting {
            Section {
                NavigationLink {
                    CardReviewSessionView(cards: dueCards, dismissWhenComplete: true)
                } label: {
                    Text(L10n.libraryReviewDeck(deck.name, count: dueCards.count))
                        .font(AppFont.helper().weight(.medium))
                        .foregroundStyle(AppColor.accent)
                }
                .buttonStyle(SoftPressButtonStyle(pressedScale: 0.99, pressedOpacity: 0.9))
                .tint(AppColor.accent)
            }
        }

        ForEach(groups.prefix(visibleItemCount)) { group in
            Section {
                ForEach(group.cardIDs, id: \.self) { cardID in
                    if let card = cardsByID[cardID] {
                        cardRow(card: card, cardID: cardID)
                    }
                }
                .onDelete(perform: isSelecting ? nil : { offsets in
                    deleteCards(in: group, at: offsets)
                })

                if !isSelecting,
                   group.cardIDs.count > 1,
                   let reviewCards = resolvedCards(for: group.cardIDs) {
                    NavigationLink {
                        CardReviewSessionView(cards: reviewCards, dismissWhenComplete: true)
                    } label: {
                        Text(L10n.reviewAll(group.word, count: group.cardIDs.count))
                            .font(AppFont.helper().weight(.medium))
                            .foregroundStyle(AppColor.accent)
                    }
                    .buttonStyle(SoftPressButtonStyle(pressedScale: 0.99, pressedOpacity: 0.9))
                    .tint(AppColor.accent)
                }
            } header: {
                AppSectionHeader(title: group.word)
            }
        }
    }

    @ViewBuilder
    private func cardRow(card: FlashCard, cardID: UUID) -> some View {
        let row = LibraryCardRow(
            card: card,
            showsDeckName: filterDeckID == nil,
            searchHighlight: searchText,
            showsSelection: isSelecting,
            isSelected: selectedCardIDs.contains(cardID)
        )

        if isSelecting {
            Button {
                toggleSelection(cardID)
            } label: {
                row
            }
            .buttonStyle(SoftPressButtonStyle(pressedScale: 0.99, pressedOpacity: 0.92))
        } else {
            NavigationLink {
                FlashCardDetailView(card: card)
            } label: {
                row
            }
            .buttonStyle(SoftPressButtonStyle(pressedScale: 0.99, pressedOpacity: 0.92))
        }
    }

    private func toggleSelection(_ cardID: UUID) {
        if selectedCardIDs.contains(cardID) {
            selectedCardIDs.remove(cardID)
        } else {
            selectedCardIDs.insert(cardID)
        }
    }

    private var currentTotalItems: Int {
        useFlatList ? flatCardIDs.count : groups.count
    }

    @MainActor
    private func rebuildGroups() async {
        let shouldShowLoading = groups.isEmpty && flatCardIDs.isEmpty
        if shouldShowLoading {
            isLoadingGroups = true
        }
        if lastGroupingToken != groupingToken {
            visibleItemCount = LibraryCardGrouper.groupPageSize
            lastGroupingToken = groupingToken
        }
        defer { isLoadingGroups = false }

        if shouldShowLoading {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(16))
        }

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
        listedCardIDs = useFlatList ? flatCardIDs : groups.flatMap(\.cardIDs)
        selectedCardIDs = selectedCardIDs.intersection(listedCardIDs)
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
        case .appreciation:
            return baseCards.filter { $0.cardType == .appreciation }
        }
    }

    private func resolvedCards(for ids: [UUID]) -> [FlashCard]? {
        let resolved = ids.compactMap { cardsByID[$0] }
        return resolved.count == ids.count ? resolved : nil
    }

    private func deleteCards(in group: LibraryWordGroup, at offsets: IndexSet) {
        let ids = Set(offsets.compactMap { group.cardIDs[safe: $0] })
        deleteCards(ids: ids)
    }

    private func deleteFlatCards(at offsets: IndexSet) {
        let ids = Set(offsets.compactMap { flatCardIDs[safe: $0] })
        deleteCards(ids: ids)
    }

    private func deleteCards(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let cards = ids.compactMap { cardsByID[$0] }
        removeFromSnapshot(ids: ids)
        selectedCardIDs.subtract(ids)

        for card in cards {
            DeckCardCountService.adjust(deck: card.deck, by: -1, in: modelContext, save: false)
            modelContext.delete(card)
        }
        try? modelContext.save()
        onCardsDeleted()
    }

    private func migrateSelected(to deckID: UUID) {
        guard let target = decks.first(where: { $0.id == deckID }) else { return }
        let cards = selectedCardIDs.compactMap { cardsByID[$0] }
        guard !cards.isEmpty else { return }

        let moved = DeckCardCountService.moveCards(cards, to: target, in: modelContext)
        guard moved > 0 else { return }

        if let filterDeckID, filterDeckID != target.id {
            let movedIDs = Set(cards.compactMap { card in
                card.deck?.id == target.id ? card.id : nil
            })
            removeFromSnapshot(ids: movedIDs)
            selectedCardIDs.subtract(movedIDs)
        }

        SharedDedupeSync.rebuild(in: modelContext)
        DeckCardCountService.notifyCatalogChanged()
        ToastCenter.shared.show(L10n.libraryMigrateDone(moved, target.name))
    }

    private func removeFromSnapshot(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        cards.removeAll { ids.contains($0.id) }
        dueCards.removeAll { ids.contains($0.id) }
        ids.forEach { cardsByID.removeValue(forKey: $0) }
        if useFlatList {
            flatCardIDs.removeAll { ids.contains($0) }
        } else {
            groups = groups.compactMap { group in
                let remaining = group.cardIDs.filter { !ids.contains($0) }
                guard !remaining.isEmpty else { return nil }
                return LibraryWordGroup(wordKey: group.wordKey, word: group.word, cardIDs: remaining)
            }
        }
        listedCardIDs = useFlatList ? flatCardIDs : groups.flatMap(\.cardIDs)
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
    var showsSelection: Bool = false
    var isSelected: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.sm) {
            if showsSelection {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isSelected ? AppColor.accent : AppColor.textTertiary)
                    .accessibilityHidden(true)
            }

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

            VStack(alignment: .trailing, spacing: 2) {
                Text(card.cardType.displayName)
                    .font(AppFont.weak())
                    .foregroundStyle(AppColor.textMuted.opacity(0.85))
                LibraryCardStatusChip(card: card)
            }
        }
        .padding(.vertical, 4)
        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        .listRowSeparatorTint(AppColor.borderSubtle)
    }

    private var contextLine: String {
        if card.cardType == .appreciation {
            let trimmedSentence = card.sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedSentence.isEmpty {
                return trimmedSentence
            }
        }

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

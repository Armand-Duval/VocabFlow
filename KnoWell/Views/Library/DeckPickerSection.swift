import SwiftUI
import SwiftData

struct DeckPickerSection: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var selectedDeckID: UUID?

    @Query(sort: [SortDescriptor(\Deck.sortOrder), SortDescriptor(\Deck.createdAt)])
    private var queriedDecks: [Deck]

    @State private var cachedDecks: [Deck] = []
    @State private var hasAttemptedLoad = false

    private var decks: [Deck] {
        queriedDecks.isEmpty ? cachedDecks : queriedDecks
    }

    var body: some View {
        Section {
            if !hasAttemptedLoad && decks.isEmpty {
                ProgressView(L10n.deckLoading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if decks.isEmpty {
                Text(L10n.deckEmpty)
                    .foregroundStyle(.secondary)
            } else {
                Picker(L10n.deckTarget, selection: deckSelection) {
                    ForEach(decks) { deck in
                        Text(deckLabel(deck)).tag(deck.id)
                    }
                }
            }

            NavigationLink {
                DeckStoreView(selectedDeckID: $selectedDeckID)
            } label: {
                Label(L10n.deckManage, systemImage: "books.vertical")
            }
        } header: {
            AppSectionHeader(title: L10n.deckSection)
        }
        .task {
            await reloadDecks()
        }
        .onAppear {
            normalizeSelection()
        }
        .onChange(of: queriedDecks.map(\.id)) { _, _ in
            normalizeSelection()
        }
        .onReceive(NotificationCenter.default.publisher(for: .libraryCatalogDidChange)) { _ in
            cachedDecks = DeckService.refreshDecks(in: modelContext)
            normalizeSelection()
        }
    }

    @MainActor
    private func reloadDecks() async {
        cachedDecks = DeckService.refreshDecks(in: modelContext)
        hasAttemptedLoad = true
        normalizeSelection()
    }

    private var deckSelection: Binding<UUID> {
        Binding(
            get: {
                if let selectedDeckID,
                   decks.contains(where: { $0.id == selectedDeckID }) {
                    return selectedDeckID
                }
                return decks.first?.id ?? UUID()
            },
            set: { newValue in
                selectedDeckID = newValue
                DeckSettings.lastSelectedDeckID = newValue
                DeckService.syncSharedCatalog(in: modelContext)
            }
        )
    }

    private func normalizeSelection() {
        if let selectedDeckID,
           decks.contains(where: { $0.id == selectedDeckID }) {
            return
        }
        let fallback = DeckSettings.lastSelectedDeckID
            ?? DeckService.fetchOrCreateDefault(in: modelContext).id
        if decks.contains(where: { $0.id == fallback }) {
            selectedDeckID = fallback
        } else if let first = decks.first?.id {
            selectedDeckID = first
        }
    }

    private func deckLabel(_ deck: Deck) -> String {
        deck.name
    }
}

struct CreateDeckPickerCard: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var selectedDeckID: UUID?

    @Query(sort: [SortDescriptor(\Deck.sortOrder), SortDescriptor(\Deck.createdAt)])
    private var queriedDecks: [Deck]

    @State private var cachedDecks: [Deck] = []
    @State private var hasAttemptedLoad = false
    @State private var showDeckPicker = false

    private var decks: [Deck] {
        queriedDecks.isEmpty ? cachedDecks : queriedDecks
    }

    private var selectedDeckName: String {
        decks.first(where: { $0.id == selectedDeckID })?.name
            ?? decks.first?.name
            ?? L10n.deckDefaultName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            if !hasAttemptedLoad && decks.isEmpty {
                ProgressView(L10n.deckLoading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if decks.isEmpty {
                Text(L10n.deckEmpty)
                    .font(AppFont.secondary())
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: AppSpacing.sm) {
                    Button {
                        showDeckPicker = true
                    } label: {
                        HStack(spacing: 6) {
                            Text(selectedDeckName)
                                .font(AppFont.secondary().weight(.medium))
                                .foregroundStyle(AppColor.textPrimary)
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(AppColor.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)

                    NavigationLink {
                        DeckStoreView(selectedDeckID: $selectedDeckID)
                    } label: {
                        Text(L10n.deckManage)
                            .font(AppFont.caption())
                            .foregroundStyle(AppColor.accent)
                    }
                }
            }
        }
        .appSelectionSheet(
            isPresented: $showDeckPicker,
            title: L10n.deckTarget,
            options: decks.map { AppSelectionOption(id: $0.id, title: deckLabel($0)) },
            selectedID: selectedDeckID ?? decks.first?.id
        ) { newValue in
            deckSelection.wrappedValue = newValue
        }
        .task {
            await reloadDecks()
        }
        .onAppear {
            normalizeSelection()
        }
        .onChange(of: queriedDecks.map(\.id)) { _, _ in
            normalizeSelection()
        }
        .onReceive(NotificationCenter.default.publisher(for: .libraryCatalogDidChange)) { _ in
            cachedDecks = DeckService.refreshDecks(in: modelContext)
            normalizeSelection()
        }
    }

    @MainActor
    private func reloadDecks() async {
        cachedDecks = DeckService.refreshDecks(in: modelContext)
        hasAttemptedLoad = true
        normalizeSelection()
    }

    private var deckSelection: Binding<UUID> {
        Binding(
            get: {
                if let selectedDeckID,
                   decks.contains(where: { $0.id == selectedDeckID }) {
                    return selectedDeckID
                }
                return decks.first?.id ?? UUID()
            },
            set: { newValue in
                selectedDeckID = newValue
                DeckSettings.lastSelectedDeckID = newValue
                DeckService.syncSharedCatalog(in: modelContext)
            }
        )
    }

    private func normalizeSelection() {
        if let selectedDeckID,
           decks.contains(where: { $0.id == selectedDeckID }) {
            return
        }
        let fallback = DeckSettings.lastSelectedDeckID
            ?? DeckService.fetchOrCreateDefault(in: modelContext).id
        if decks.contains(where: { $0.id == fallback }) {
            selectedDeckID = fallback
        } else if let first = decks.first?.id {
            selectedDeckID = first
        }
    }

    private func deckLabel(_ deck: Deck) -> String {
        deck.name
    }
}

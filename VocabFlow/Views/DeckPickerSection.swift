import SwiftUI
import SwiftData

struct DeckPickerSection: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var selectedDeckID: UUID?

    @Query(sort: [SortDescriptor(\Deck.sortOrder), SortDescriptor(\Deck.createdAt)])
    private var decks: [Deck]

    var body: some View {
        Section {
            if decks.isEmpty {
                Text(L10n.deckLoading)
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
            Text(L10n.deckSection)
        } footer: {
            Text(L10n.deckSectionFooter)
        }
        .onAppear {
            normalizeSelection()
        }
        .onChange(of: decks.map(\.id)) { _, _ in
            normalizeSelection()
        }
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
        DeckService.bootstrap(in: modelContext)
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
        if deck.cardCount > 0 {
            return L10n.deckLabelWithCount(deck.name, count: deck.cardCount)
        }
        return deck.name
    }
}

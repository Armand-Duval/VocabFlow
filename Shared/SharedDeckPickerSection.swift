import SwiftUI

struct SharedDeckPickerSection: View {
    @Binding var selectedDeckID: UUID

    @State private var decks: [SharedDeckEntry] = []

    var body: some View {
        Section {
            if decks.isEmpty {
                Text(L10n.deckExtensionEmptyCatalogHint)
                    .font(AppFont.caption())
                    .foregroundStyle(.secondary)
            } else {
                Picker(L10n.deckTarget, selection: $selectedDeckID) {
                    ForEach(decks) { deck in
                        Text(deck.name).tag(deck.id)
                    }
                }
                .onChange(of: selectedDeckID) { _, newValue in
                    SharedDeckStore.lastSelectedDeckID = newValue
                }
            }
        } header: {
            AppSectionHeader(title: L10n.deckSection)
        }
        .onAppear {
            reloadDecks()
        }
    }

    private func reloadDecks() {
        decks = SharedDeckStore.loadCatalog()
        if let resolved = SharedDeckStore.resolvedSelectedDeckID(),
           decks.contains(where: { $0.id == resolved }) {
            selectedDeckID = resolved
        } else if let first = decks.first?.id {
            selectedDeckID = first
            SharedDeckStore.lastSelectedDeckID = first
        }
    }
}

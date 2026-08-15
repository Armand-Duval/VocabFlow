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
                AppSpinner(
                    title: L10n.deckTarget,
                    value: decks.first(where: { $0.id == selectedDeckID })?.name ?? L10n.deckDefaultName,
                    options: decks.map { AppSelectionOption(id: $0.id, title: $0.name) },
                    selectedID: selectedDeckID.uuidString
                ) { raw in
                    if let id = UUID(uuidString: raw) {
                        selectedDeckID = id
                        SharedDeckStore.lastSelectedDeckID = id
                    }
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

import SwiftUI
import SwiftData

struct CardPreviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var selectedDeckID: UUID?
    @State private var drafts: [GeneratedCardDraft]
    var onComplete: () -> Void

    init(drafts: [GeneratedCardDraft], selectedDeckID: Binding<UUID?>, onComplete: @escaping () -> Void) {
        _drafts = State(initialValue: drafts)
        _selectedDeckID = selectedDeckID
        self.onComplete = onComplete
    }

    private var selectedCount: Int {
        drafts.filter(\.isSelected).count
    }

    var body: some View {
        Form {
            DeckPickerSection(selectedDeckID: $selectedDeckID)

            Section {
                ForEach($drafts) { $draft in
                    DraftPreviewCard(draft: $draft)
                }
            } header: {
                Text(L10n.createPreviewSectionCards)
            } footer: {
                Text(L10n.createPreviewFooterCompact)
            }
        }
        .navigationTitle(L10n.previewTitle)
        .navigationBarTitleDisplayMode(.inline)
        .dismissKeyboardOnScroll()
        .keyboardDoneButton()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(L10n.saveCount(selectedCount)) {
                    saveSelectedCards()
                }
                .fontWeight(.semibold)
                .disabled(selectedCount == 0)
            }
        }
    }

    private func saveSelectedCards() {
        let deck = DeckService.resolvedDeck(id: selectedDeckID, in: modelContext)
        let result = FlashCardSaver.save(drafts: drafts, to: modelContext, deck: deck)

        if result.skippedAll {
            ToastCenter.shared.show(L10n.saveAllDuplicatesMessage)
            return
        }

        guard result.didSaveAny else { return }

        selectedDeckID = deck.id
        if result.skippedDuplicateCount > 0 {
            ToastCenter.shared.show(
                L10n.savePartialDuplicates(result.savedCount, skipped: result.skippedDuplicateCount)
            )
        } else {
            ToastCenter.shared.show(L10n.savedMessage)
        }
        onComplete()
    }
}

#Preview {
    NavigationStack {
        CardPreviewView(
            drafts: [
                GeneratedCardDraft(
                    word: "mitigate",
                    phonetic: "/ˈmɪtɪɡeɪt/",
                    sentence: "Sample sentence.",
                    cardType: .cloze,
                    front: "The govt tried to ______ the impact.",
                    back: "mitigate v. 减轻\n\n在此句中表示减轻、缓解影响。",
                    contextNote: nil
                )
            ],
            selectedDeckID: .constant(nil)
        ) {}
    }
    .modelContainer(for: [Deck.self, FlashCard.self], inMemory: true)
}

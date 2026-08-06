import SwiftUI
import SwiftData

struct CardPreviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var selectedDeckID: UUID?
    @State private var drafts: [GeneratedCardDraft]
    var onComplete: () -> Void

    @State private var didSave = false
    @State private var saveAlertTitle = L10n.savedTitle
    @State private var saveAlertMessage = L10n.savedMessage

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
        .alert(saveAlertTitle, isPresented: $didSave) {
            Button(L10n.done) {
                onComplete()
            }
        } message: {
            Text(saveAlertMessage)
        }
    }

    private func saveSelectedCards() {
        let deck = DeckService.resolvedDeck(id: selectedDeckID, in: modelContext)
        let result = FlashCardSaver.save(drafts: drafts, to: modelContext, deck: deck)

        if result.skippedAll {
            saveAlertTitle = L10n.saveAllDuplicatesTitle
            saveAlertMessage = L10n.saveAllDuplicatesMessage
            didSave = true
            return
        }

        guard result.didSaveAny else { return }

        selectedDeckID = deck.id
        saveAlertTitle = L10n.savedTitle
        if result.skippedDuplicateCount > 0 {
            saveAlertMessage = L10n.savePartialDuplicates(
                result.savedCount,
                skipped: result.skippedDuplicateCount
            )
        } else {
            saveAlertMessage = L10n.savedMessage
        }
        didSave = true
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

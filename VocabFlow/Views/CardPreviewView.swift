import SwiftUI
import SwiftData

struct CardPreviewView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var drafts: [GeneratedCardDraft]
    var onComplete: () -> Void

    @State private var didSave = false

    init(drafts: [GeneratedCardDraft], onComplete: @escaping () -> Void) {
        _drafts = State(initialValue: drafts)
        self.onComplete = onComplete
    }

    private var selectedCount: Int {
        drafts.filter(\.isSelected).count
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach($drafts) { $draft in
                    DraftPreviewCard(draft: $draft)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
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
        .alert(L10n.savedTitle, isPresented: $didSave) {
            Button(L10n.done) {
                onComplete()
            }
        }
    }

    private func saveSelectedCards() {
        let count = FlashCardSaver.save(drafts: drafts, to: modelContext)
        guard count > 0 else { return }
        didSave = true
    }
}

#Preview {
    NavigationStack {
        CardPreviewView(drafts: [
            GeneratedCardDraft(
                word: "mitigate",
                phonetic: "/ˈmɪtɪɡeɪt/",
                sentence: "Sample sentence.",
                cardType: .cloze,
                front: "The govt tried to ______ the impact.",
                back: "mitigate v. 减轻\n\n在此句中表示减轻、缓解影响。",
                contextNote: nil
            )
        ]) {}
    }
    .modelContainer(for: FlashCard.self, inMemory: true)
}

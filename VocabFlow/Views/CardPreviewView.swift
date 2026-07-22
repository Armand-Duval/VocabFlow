import SwiftUI
import SwiftData

struct CardPreviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var drafts: [GeneratedCardDraft]
    var onComplete: () -> Void

    @State private var didSave = false

    private var selectedCount: Int {
        drafts.filter(\.isSelected).count
    }

    var body: some View {
        List {
            Section {
                Text(L10n.previewIntro)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach($drafts) { $draft in
                Section {
                    Toggle(L10n.includeInLibrary, isOn: $draft.isSelected)

                    LabeledContent(L10n.wordLabel) {
                        TextField(L10n.wordLabel, text: $draft.word)
                            .multilineTextAlignment(.trailing)
                            .submitLabel(.done)
                    }

                    Picker(L10n.typeLabel, selection: $draft.cardType) {
                        ForEach(CardType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.frontLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField(L10n.frontLabel, text: $draft.front, axis: .vertical)
                            .lineLimit(4...30)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.backLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField(L10n.backPlaceholder, text: $draft.back, axis: .vertical)
                            .lineLimit(4...30)
                    }
                } header: {
                    Text("\(draft.word) · \(draft.cardType.displayName)")
                }
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
                .disabled(selectedCount == 0)
            }
        }
        .alert(L10n.savedTitle, isPresented: $didSave) {
            Button(L10n.done) {
                onComplete()
            }
        } message: {
            Text(L10n.savedMessage)
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
        CardPreviewView(drafts: .constant([
            GeneratedCardDraft(
                word: "mitigate",
                sentence: "Sample sentence.",
                cardType: .cloze,
                front: "The govt tried to ______ the impact.",
                back: "mitigate v. 减轻\n\n在此句中表示减轻、缓解影响。",
                contextNote: nil
            )
        ])) {}
    }
    .modelContainer(for: FlashCard.self, inMemory: true)
}

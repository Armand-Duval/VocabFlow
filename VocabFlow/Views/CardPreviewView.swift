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
                Text("预览并编辑 AI 生成的卡片，确认后保存到词库。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach($drafts) { $draft in
                Section {
                    Toggle("加入词库", isOn: $draft.isSelected)

                    LabeledContent("生词") {
                        TextField("生词", text: $draft.word)
                            .multilineTextAlignment(.trailing)
                            .submitLabel(.done)
                    }

                    Picker("类型", selection: $draft.cardType) {
                        ForEach(CardType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("正面")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("正面", text: $draft.front, axis: .vertical)
                            .lineLimit(4...30)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("背面")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("释义、词性、语境说明", text: $draft.back, axis: .vertical)
                            .lineLimit(4...30)
                    }
                } header: {
                    Text("\(draft.word) · \(draft.cardType.displayName)")
                }
            }
        }
        .navigationTitle("预览卡片")
        .navigationBarTitleDisplayMode(.inline)
        .dismissKeyboardOnScroll()
        .keyboardDoneButton()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存 \(selectedCount) 张") {
                    saveSelectedCards()
                }
                .disabled(selectedCount == 0)
            }
        }
        .alert("已保存", isPresented: $didSave) {
            Button("完成") {
                onComplete()
            }
        } message: {
            Text("卡片已加入词库，可以去「复习」标签开始记忆。")
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

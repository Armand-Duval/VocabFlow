import SwiftUI

struct ImportCardsFormView: View {
    let onSubmit: () -> Void
    let onCancel: () -> Void

    @State private var sentence: String
    @State private var wordsText: String
    @State private var selectedText = ""
    @State private var selectionClearNonce = 0
    @State private var errorMessage: String?

    init(
        sentence: String,
        selectedWord: String? = nil,
        onSubmit: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        _sentence = State(initialValue: sentence)
        _wordsText = State(initialValue: selectedWord ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label {
                        Text("拖选生词后点「AI 生成卡片」，将立即返回并后台制卡")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "sparkles")
                    }
                }

                Section {
                    ZStack(alignment: .topLeading) {
                        SelectableTextEditor(
                            text: $sentence,
                            selectedText: $selectedText,
                            selectionClearNonce: $selectionClearNonce,
                            onAddToVocabulary: appendSelectionToWords
                        )

                        if sentence.isEmpty {
                            Text("粘贴原文句子")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .allowsHitTesting(false)
                        }
                    }

                    if !selectedText.isEmpty {
                        Button {
                            appendSelectionToWords()
                        } label: {
                            Label("加入生词：\(selectedText)", systemImage: "plus.circle.fill")
                                .font(.subheadline)
                        }
                    }
                } header: {
                    Text("原文")
                } footer: {
                    Text("拖选文字后点「加入生词」，或长按选区菜单选择。")
                }

                Section {
                    TextField("生词或短语，用逗号分隔", text: $wordsText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("生词")
                } footer: {
                    Text("至少填写一个生词。生成结果将通过通知告知。")
                }
            }
            .navigationTitle("制卡")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        onCancel()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("AI 生成卡片") {
                        submitGeneration()
                    }
                    .fontWeight(.semibold)
                    .disabled(trimmedSentence.isEmpty || parsedWords.isEmpty)
                }
            }
            .alert("无法提交", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var trimmedSentence: String {
        sentence.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsedWords: [String] {
        wordsText
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func appendSelectionToWords() {
        let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var words = parsedWords
        guard !words.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            selectionClearNonce += 1
            return
        }

        words.append(trimmed)
        wordsText = words.joined(separator: ", ")
        selectionClearNonce += 1
    }

    private func submitGeneration() {
        guard APISettings.canUseKimi else {
            errorMessage = "未配置 Kimi API Key"
            return
        }

        ShareCardGenerationRunner.submitFromShareExtension(
            sentence: trimmedSentence,
            words: parsedWords,
            exitExtension: onSubmit
        )
    }
}

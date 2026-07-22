import SwiftUI

struct CreateCardsView: View {
    @EnvironmentObject private var shareImport: ShareImportCoordinator
    @State private var sentence = ""
    @State private var words: [String] = []
    @State private var drafts: [GeneratedCardDraft] = []
    @State private var isGenerating = false
    @State private var showPreview = false
    @State private var errorMessage: String?
    @State private var didApplyShareImport = false
    @State private var importBannerMessage: String?
    @State private var selectedText = ""
    @State private var selectionClearNonce = 0
    @State private var wordFeedbackMessage: String?
    @State private var wordFeedbackIsError = false

    var body: some View {
        NavigationStack {
            Form {
                if didApplyShareImport, let importBannerMessage {
                    Section {
                        Label(importBannerMessage, systemImage: "doc.on.clipboard")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
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
                    Text("拖选文字后点「加入生词」，或长按选区菜单选择。Safari 可分享导入；Apple Books、番茄小说等请复制文字后打开 App，会自动填入。")
                }

                Section {
                    VocabularyWordsEditor(
                        words: $words,
                        feedbackMessage: $wordFeedbackMessage,
                        feedbackIsError: $wordFeedbackIsError
                    )
                } header: {
                    Text("生词")
                } footer: {
                    Text("点击标签上的 × 可移除生词。")
                }

                Section {
                    Button {
                        generateCards()
                    } label: {
                        HStack {
                            Spacer()
                            if isGenerating {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text(isGenerating ? "生成中..." : "AI 生成卡片")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(isGenerating || sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || words.isEmpty)

                    if APISettings.isUsingDefaultKey {
                        Text("当前使用内置默认 API Key")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("制卡")
            .dismissKeyboardOnScroll()
            .keyboardDoneButton()
            .navigationDestination(isPresented: $showPreview) {
                CardPreviewView(drafts: $drafts) {
                    showPreview = false
                }
            }
            .onChange(of: showPreview) { _, isShowing in
                if !isShowing {
                    drafts.removeAll()
                }
            }
            .alert("无法生成", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .onAppear {
                applyShareImportIfNeeded()
            }
            .onChange(of: shareImport.pendingPayload) { _, _ in
                applyShareImportIfNeeded()
            }
        }
    }

    private func appendSelectionToWords() {
        let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            wordFeedbackMessage = "选区为空"
            wordFeedbackIsError = true
            return
        }

        let result = VocabularyWords.append(trimmed, to: &words)
        switch result {
        case .added:
            selectionClearNonce += 1
            wordFeedbackMessage = "已加入「\(trimmed)」"
            wordFeedbackIsError = false
        case .duplicate:
            selectionClearNonce += 1
            wordFeedbackMessage = "「\(trimmed)」已在生词列表中"
            wordFeedbackIsError = true
        case .empty:
            wordFeedbackMessage = "选区为空"
            wordFeedbackIsError = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            wordFeedbackMessage = nil
        }
    }

    private func applyShareImportIfNeeded() {
        guard let payload = shareImport.pendingPayload else { return }
        sentence = payload.sentence
        if let word = payload.selectedWord {
            words = VocabularyWords.parse(from: word)
        }
        importBannerMessage = payload.source == .clipboard
            ? "已从剪贴板填入原文，请补充生词后生成卡片"
            : "已填入分享内容，请补充生词后生成卡片"
        didApplyShareImport = true
        shareImport.acknowledgeImport()
    }

    private func generateCards() {
        errorMessage = nil
        isGenerating = true

        Task {
            do {
                let generated = try await KimiCardGenerator.generate(sentence: sentence, words: words)

                await MainActor.run {
                    isGenerating = false
                    if generated.isEmpty {
                        errorMessage = "请填写原句，并至少输入一个生词。"
                    } else {
                        drafts = generated
                        showPreview = true
                    }
                }
            } catch {
                await MainActor.run {
                    isGenerating = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

#Preview {
    CreateCardsView()
        .environmentObject(ShareImportCoordinator())
}

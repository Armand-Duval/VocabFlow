import SwiftUI

struct CreateCardsView: View {
    @EnvironmentObject private var shareImport: ShareImportCoordinator
    @AppStorage("createCards.tipDismissed") private var tipDismissed = false
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
                if !tipDismissed && !didApplyShareImport {
                    Section {
                        CreateCardsTipView {
                            tipDismissed = true
                        }
                    }
                }

                if didApplyShareImport, let importBannerMessage {
                    Section {
                        ImportBannerView(
                            message: importBannerMessage,
                            systemImage: "doc.on.clipboard"
                        )
                    }
                    .listRowBackground(Color.accentColor.opacity(0.08))
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
                            Text(L10n.sourcePlaceholder)
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .allowsHitTesting(false)
                        }
                    }

                    if !selectedText.isEmpty {
                        AddSelectionButton(selectedText: selectedText, action: appendSelectionToWords)
                    }
                } header: {
                    Label(L10n.sourceText, systemImage: "doc.text")
                } footer: {
                    Text(L10n.sourceFooter)
                }

                Section {
                    VocabularyWordsEditor(
                        words: $words,
                        feedbackMessage: $wordFeedbackMessage,
                        feedbackIsError: $wordFeedbackIsError
                    )
                } header: {
                    Label(L10n.wordsSection, systemImage: "character.book.closed")
                } footer: {
                    Text(L10n.wordsFooter)
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
                            Text(isGenerating ? L10n.generating : L10n.generateCards)
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(isGenerating || sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || words.isEmpty)

                    if APISettings.isUsingDefaultKey {
                        Text(L10n.usingDefaultKey)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle(L10n.createTitle)
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
            .alert(L10n.generateFailedTitle, isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button(L10n.ok, role: .cancel) {}
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
            wordFeedbackMessage = L10n.selectionEmpty
            wordFeedbackIsError = true
            return
        }

        let result = VocabularyWords.append(trimmed, to: &words)
        if case .added = result {
            selectionClearNonce += 1
        } else if case .duplicate = result {
            selectionClearNonce += 1
        }
        VocabularyWordFeedback.apply(result, message: &wordFeedbackMessage, isError: &wordFeedbackIsError)
        clearFeedbackLater()
    }

    private func clearFeedbackLater() {
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
        importBannerMessage = payload.bannerMessage
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
                        errorMessage = L10n.generateEmptyError
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

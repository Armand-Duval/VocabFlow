import SwiftUI

struct ImportCardsFormView: View {
    let onSubmit: () -> Void
    let onCancel: () -> Void

    @State private var sentence: String
    @State private var words: [String]
    @State private var selectedText = ""
    @State private var selectionClearNonce = 0
    @State private var wordFeedbackMessage: String?
    @State private var wordFeedbackIsError = false
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
        _words = State(initialValue: selectedWord.map { VocabularyWords.parse(from: $0) } ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.sourceText) {
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
                        SelectionActionBar(selectedText: selectedText, action: appendSelectionToWords)
                    }
                }

                Section(L10n.wordsSection) {
                    VocabularyWordsEditor(
                        words: $words,
                        feedbackMessage: $wordFeedbackMessage,
                        feedbackIsError: $wordFeedbackIsError
                    )
                }
            }
            .navigationTitle(L10n.createTitle)
            .navigationBarTitleDisplayMode(.inline)
            .dismissKeyboardOnScroll()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel, action: onCancel)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.generateCards, action: submitGeneration)
                        .fontWeight(.semibold)
                        .disabled(trimmedSentence.isEmpty || words.isEmpty)
                }
            }
            .alert(L10n.extensionSubmitFailedTitle, isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button(L10n.ok, role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var trimmedSentence: String {
        sentence.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private func submitGeneration() {
        guard APISettings.canUseKimi else {
            errorMessage = L10n.extensionMissingKey
            return
        }

        ShareCardGenerationRunner.submitFromShareExtension(
            sentence: trimmedSentence,
            words: words,
            exitExtension: onSubmit
        )
    }
}

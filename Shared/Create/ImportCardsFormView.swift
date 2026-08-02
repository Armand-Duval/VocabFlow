import SwiftUI

struct ImportCardsFormView: View {
    let onSubmit: () -> Void
    let onCancel: () -> Void
    private let sourceHint: String?
    private let sourceImagePath: String?

    @State private var sentence: String
    @State private var words: [String]
    @State private var selectedText = ""
    @State private var selectionClearNonce = 0
    @State private var wordFeedbackMessage: String?
    @State private var wordFeedbackIsError = false
    @State private var errorMessage: String?
    @State private var selectedDeckID = UUID()

    init(
        sentence: String,
        selectedWord: String? = nil,
        sourceHint: String? = nil,
        sourceImagePath: String? = nil,
        onSubmit: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        self.sourceHint = sourceHint
        self.sourceImagePath = sourceImagePath
        _sentence = State(initialValue: sentence)
        _words = State(initialValue: selectedWord.map { VocabularyWords.parse(from: $0) } ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                if sourceImagePath != nil {
                    Section {
                        CardSourceImageThumbnail(relativePath: sourceImagePath, maxHeight: 120)
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

                Section {
                    VocabularyWordsEditor(
                        words: $words,
                        feedbackMessage: $wordFeedbackMessage,
                        feedbackIsError: $wordFeedbackIsError,
                        deckContainsWord: { word in
                            wordExistsInSelectedDeck(word)
                        }
                    )
                }

                SharedDeckPickerSection(selectedDeckID: $selectedDeckID)
            }
            .navigationTitle(L10n.createTitle)
            .navigationBarTitleDisplayMode(.inline)
            .dismissKeyboardOnScroll()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel, action: onCancel)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.generateCardsShort, action: submitGeneration)
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

    private func wordExistsInSelectedDeck(_ word: String) -> Bool {
        let units = KimiCardGenerator.makeGenerationUnits(sentence: trimmedSentence, words: [word])
        if units.isEmpty {
            return SharedDedupeIndex.contains(
                deckID: selectedDeckID,
                word: word,
                sentence: trimmedSentence
            )
        }
        return units.contains {
            SharedDedupeIndex.contains(
                deckID: selectedDeckID,
                word: word,
                sentence: $0.sentence
            )
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

    private func submitGeneration() {
        guard APISettings.canUseKimi else {
            errorMessage = L10n.extensionMissingKey
            return
        }

        guard !SharedDeckStore.loadCatalog().isEmpty else {
            errorMessage = L10n.deckExtensionEmptyCatalogHint
            return
        }

        ShareCardGenerationRunner.submitFromShareExtension(
            sentence: trimmedSentence,
            words: words,
            sourceHint: sourceHint,
            sourceImagePath: sourceImagePath,
            targetDeckID: selectedDeckID,
            exitExtension: onSubmit
        )
    }
}

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Extension create workspace — mirrors main `CreateCardsView` layout (without SwiftData / camera queue).
struct ImportCardsFormView: View {
    let onSubmit: () -> Void
    let onCancel: () -> Void
    private let sourceHint: String?
    private let sourceImagePath: String?

    @State private var sentence: String
    @State private var words: [String]
    @State private var selectedText = ""
    @State private var selectionClearNonce = 0
    @State private var isSourceFocused = false
    @State private var sourceMode: SourceWorkspaceMode
    @State private var wordFeedbackMessage: String?
    @State private var wordFeedbackIsError = false
    @State private var errorMessage: String?
    @State private var selectedDeckID = UUID()
    @State private var decks: [SharedDeckEntry] = []

    private enum SourceWorkspaceMode: String, CaseIterable, Identifiable {
        case edit
        case pick

        var id: String { rawValue }

        var title: String {
            switch self {
            case .edit: return L10n.createSourceModeEdit
            case .pick: return L10n.createSourceModePick
            }
        }
    }

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
        let initialWords = selectedWord.map { VocabularyWords.parse(from: $0) } ?? []
        _words = State(initialValue: initialWords)
        let hasSentence = !sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        _sourceMode = State(initialValue: hasSentence ? .pick : .edit)
    }

    private var trimmedSentence: String {
        sentence.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canGenerate: Bool {
        !trimmedSentence.isEmpty && !words.isEmpty
    }

    private var generateDisabledHint: String? {
        guard !canGenerate else { return nil }
        if trimmedSentence.isEmpty && words.isEmpty {
            return L10n.createGenerateNeedBoth
        }
        if trimmedSentence.isEmpty {
            return L10n.createGenerateNeedSentence
        }
        return L10n.createGenerateNeedWords
    }

    var body: some View {
        NavigationStack {
            scrollContent
                .appPageBackground()
                .navigationTitle(L10n.createTitle)
                .navigationBarTitleDisplayMode(.inline)
                .dismissKeyboardOnScroll()
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    generateFooter
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.cancel, action: onCancel)
                    }
                }
                .appToast(bottomPadding: 120)
                .onChange(of: errorMessage) { _, message in
                    guard let message, !message.isEmpty else { return }
                    ToastCenter.shared.show(message)
                    errorMessage = nil
                }
                .onAppear { reloadDecks() }
                .onChange(of: trimmedSentence.isEmpty) { _, isEmpty in
                    if isEmpty { sourceMode = .edit }
                }
        }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                if sourceImagePath != nil {
                    CardSourceImageThumbnail(relativePath: sourceImagePath, maxHeight: 120)
                        .frame(maxWidth: .infinity)
                }

                if let sourceHint, !sourceHint.isEmpty {
                    Text(sourceHint)
                        .font(AppFont.helper())
                        .foregroundStyle(AppColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                pasteToolbar

                if trimmedSentence.isEmpty {
                    sourceEditSurface(minHeight: 120, showPlaceholder: true)
                } else {
                    sourceWorkspace

                    if sourceMode == .edit, !selectedText.isEmpty {
                        SelectionActionBar(selectedText: selectedText, action: appendSelectionToWords)
                    }
                }

                deckPickerCard
                wordsCard
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.top, AppSpacing.md)
            .padding(.bottom, AppSpacing.md)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var pasteToolbar: some View {
        HStack(spacing: AppSpacing.sm) {
            Button {
                pasteFromClipboard()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 14, weight: .regular))
                    Text(L10n.createQuickPaste)
                        .font(AppFont.helper().weight(.medium))
                }
                .foregroundStyle(AppColor.textSecondary)
                .padding(.horizontal, AppSpacing.sm)
                .frame(minHeight: 36)
                .background(
                    AppColor.surfaceMuted,
                    in: RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous)
                )
                .appSoftShadow()
            }
            .buttonStyle(SoftPressButtonStyle())
            .accessibilityLabel(L10n.createQuickPaste)

            Spacer(minLength: 0)
        }
    }

    private var sourceWorkspace: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Picker("", selection: $sourceMode) {
                ForEach(SourceWorkspaceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: sourceMode) { _, mode in
                if mode == .pick {
                    isSourceFocused = false
                }
            }

            switch sourceMode {
            case .edit:
                sourceEditSurface(minHeight: 120, showPlaceholder: false)
            case .pick:
                PhraseTokenPicker(
                    sentence: trimmedSentence,
                    words: $words,
                    maxContentHeight: 220,
                    showsChrome: false,
                    onCommitPhrase: { phrase in
                        let result = VocabularyWords.append(phrase, to: &words)
                        VocabularyWordFeedback.apply(
                            result,
                            message: &wordFeedbackMessage,
                            isError: &wordFeedbackIsError
                        )
                        clearFeedbackLater()
                        return result
                    }
                )
                .padding(AppSpacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .appInputSurface(isFocused: false)
            }
        }
    }

    private func sourceEditSurface(minHeight: CGFloat, showPlaceholder: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            SelectableTextEditor(
                text: $sentence,
                selectedText: $selectedText,
                selectionClearNonce: $selectionClearNonce,
                isFocused: $isSourceFocused,
                onAddToVocabulary: appendSelectionToWords
            )
            .frame(minHeight: minHeight)
            .padding(AppSpacing.sm)

            if showPlaceholder, sentence.isEmpty {
                Text(L10n.createPastePlaceholder)
                    .font(AppFont.literaryQuote())
                    .foregroundStyle(AppColor.textMuted)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.top, AppSpacing.md + 2)
                    .allowsHitTesting(false)
            }
        }
        .appInputSurface(isFocused: isSourceFocused)
    }

    private var deckPickerCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(L10n.deckTarget)
                .font(AppFont.helper())
                .foregroundStyle(AppColor.textMuted)

            if decks.isEmpty {
                Text(L10n.deckExtensionEmptyCatalogHint)
                    .font(AppFont.secondary())
                    .foregroundStyle(.secondary)
            } else {
                Picker(L10n.deckTarget, selection: $selectedDeckID) {
                    ForEach(decks) { deck in
                        Text(deck.name).tag(deck.id)
                    }
                }
                .labelsHidden()
                .onChange(of: selectedDeckID) { _, newValue in
                    SharedDeckStore.lastSelectedDeckID = newValue
                }
            }
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appInputSurface(isFocused: false)
        .appSoftShadow()
    }

    private var wordsCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(L10n.wordsSection)
                .font(AppFont.helper())
                .foregroundStyle(AppColor.textMuted)

            VocabularyWordsEditor(
                words: $words,
                feedbackMessage: $wordFeedbackMessage,
                feedbackIsError: $wordFeedbackIsError,
                deckContainsWord: { word in
                    wordExistsInSelectedDeck(word)
                }
            )
        }
        .padding(AppSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appInputSurface(isFocused: false)
        .appSoftShadow()
    }

    private var generateFooter: some View {
        VStack(spacing: AppSpacing.xs) {
            if let generateDisabledHint {
                Text(generateDisabledHint)
                    .font(AppFont.helper())
                    .foregroundStyle(AppColor.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppSpacing.md)
            }

            Button(action: submitGeneration) {
                Text(L10n.createAIGenerate)
            }
            .buttonStyle(PrimaryButtonStyle(prominent: true))
            .disabled(!canGenerate)
            .padding(.horizontal, AppSpacing.md)
        }
        .padding(.top, AppSpacing.sm)
        .padding(.bottom, AppSpacing.sm)
        .background(AppColor.pageBackground)
    }

    private func reloadDecks() {
        decks = SharedDeckStore.loadCatalog()
        if let resolved = SharedDeckStore.resolvedSelectedDeckID(),
           decks.contains(where: { $0.id == resolved }) {
            selectedDeckID = resolved
        } else if let first = decks.first?.id {
            selectedDeckID = first
            SharedDeckStore.lastSelectedDeckID = first
        }
    }

    private func pasteFromClipboard() {
        #if canImport(UIKit)
        if let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            sentence = text
            sourceMode = .pick
        }
        #endif
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

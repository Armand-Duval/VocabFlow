import SwiftUI
import UIKit

struct CreateCardsView: View {
    private enum LongTextSuggestion {
        case none
        case keepSingleSentence
        case splitIntoWords
    }

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var shareImport: ShareImportCoordinator
    @State private var sentence = ""
    @State private var words: [String] = []
    @State private var drafts: [GeneratedCardDraft] = []
    @State private var selectedDeckID: UUID?
    @ObservedObject private var generationQueue = CardGenerationQueue.shared
    @State private var showPreview = false
    @State private var showGenerationQueue = false
    @State private var errorMessage: String?
    @State private var selectedText = ""
    @State private var selectionClearNonce = 0
    @State private var wordFeedbackMessage: String?
    @State private var wordFeedbackIsError = false
    @State private var isRecognizingPhoto = false
    @State private var isGeneratingAppreciation = false
    @State private var generationMode: CardGenerationMode = CardGenerationPreferences.mode
    @State private var appreciationSource = ""
    @State private var showPhotoLibrary = false
    @State private var showCamera = false
    @State private var showLongTextPrompt = false
    @State private var pendingLongText = ""
    @State private var longTextChoiceMade = false
    @State private var isManualEditing = false
    @State private var sourceHint: String?
    @State private var sourceImagePath: String?
    @State private var isSourceFocused = false
    /// Edit pasted/OCR text vs pick phrases — one surface, not two stacked boxes.
    @State private var sourceMode: SourceWorkspaceMode = .edit

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

    private var trimmedSentence: String {
        sentence.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var willGenerateAppreciation: Bool {
        !trimmedSentence.isEmpty && words.isEmpty
    }

    private var canGenerate: Bool {
        !trimmedSentence.isEmpty
    }

    private var hasPendingDrafts: Bool {
        guard let drafts = shareImport.pendingDrafts else { return false }
        return !drafts.isEmpty
    }

    var body: some View {
        NavigationStack {
            scrollContent
                .appPageBackground()
                .navigationBarTitleDisplayMode(.inline)
                .dismissKeyboardOnScroll()
                .keyboardDoneButton()
                .safeAreaInset(edge: .top, spacing: 0) {
                    if generationQueue.hasActiveJobs || !generationQueue.jobs.isEmpty {
                        generationQueueBanner
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    generateFooter
                }
                .loadingOverlay(
                    isPresented: isRecognizingPhoto || isGeneratingAppreciation,
                    message: isGeneratingAppreciation ? L10n.createAppreciationGenerating : L10n.recognizingPhoto
                )
                .navigationDestination(isPresented: $showPreview) {
                    CardPreviewView(drafts: drafts, selectedDeckID: $selectedDeckID) {
                        showPreview = false
                    }
                }
                .sheet(isPresented: $showGenerationQueue) {
                    CardGenerationQueueView(queue: generationQueue)
                }
                .onChange(of: generationQueue.readyPreview) { _, preview in
                    guard let preview else { return }
                    selectedDeckID = preview.deckID
                    drafts = preview.drafts
                    showPreview = true
                    generationQueue.dismissReadyPreview()
                }
                .modifier(CreateCardsAlertsModifier(errorMessage: $errorMessage))
                .modifier(CreateCardsLifecycleModifier(
                    sentence: $sentence,
                    pendingLongText: $pendingLongText,
                    showLongTextPrompt: $showLongTextPrompt,
                    showPreview: $showPreview,
                    drafts: $drafts,
                    shareImport: shareImport,
                    onAppearImport: applyShareImportIfNeeded
                ))
                .sheet(isPresented: $showPhotoLibrary) {
                    PhotoLibraryPicker { image in
                        Task { await importCapturedImage(image, successBanner: L10n.importFromPhotoSuccess) }
                    }
                    .ignoresSafeArea()
                }
                .sheet(isPresented: $showCamera) {
                    CameraImagePicker { image in
                        Task { await importCapturedImage(image, successBanner: L10n.importFromCameraSuccess) }
                    }
                    .ignoresSafeArea()
                }
                .appActionSheet(
                    isPresented: $showLongTextPrompt,
                    title: L10n.createLongTextTitle,
                    message: L10n.createLongTextMessage,
                    actions: [
                        AppSheetAction(title: L10n.createLongTextKeepSentence, systemImage: "text.alignleft") {
                            longTextChoiceMade = true
                            applyLongTextSuggestion(.keepSingleSentence)
                        },
                        AppSheetAction(title: L10n.createLongTextSplitWords, systemImage: "list.bullet") {
                            longTextChoiceMade = true
                            applyLongTextSuggestion(.splitIntoWords)
                        }
                    ]
                )
                .onChange(of: showLongTextPrompt) { _, isPresented in
                    if !isPresented {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            if !longTextChoiceMade {
                                pendingLongText = ""
                            }
                            longTextChoiceMade = false
                        }
                    }
                }
                .onChange(of: trimmedSentence.isEmpty) { _, isEmpty in
                    if isEmpty { sourceMode = .edit }
                }
        }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                if hasPendingDrafts, let pendingDrafts = shareImport.pendingDrafts {
                    PendingCardsBannerView(
                        title: L10n.createPendingImportTitle,
                        subtitle: L10n.createPendingDraftsSubtitle(pendingDrafts.count),
                        systemImage: "sparkles.rectangle.stack.fill",
                        actionTitle: L10n.createPendingAction,
                        action: openShareDraftPreview
                    )
                }

                captureToolbar

                if trimmedSentence.isEmpty {
                    sourceEditSurface(minHeight: 72, showPlaceholder: true, placeholder: L10n.createPastePlaceholder)
                } else {
                    sourceWorkspace

                    if sourceMode == .edit, !selectedText.isEmpty {
                        SelectionActionBar(selectedText: selectedText, action: appendSelectionToWords)
                    }
                }

                if willGenerateAppreciation {
                    optionalSourceField
                }

                if isRecognizingPhoto {
                    HStack(spacing: AppSpacing.xs) {
                        ProgressView()
                        Text(L10n.recognizingPhoto)
                            .font(AppFont.helper())
                            .foregroundStyle(AppColor.textMuted)
                    }
                }

                CreateDeckPickerCard(selectedDeckID: $selectedDeckID)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, AppSpacing.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appInputSurface(isFocused: false)

                wordsCard
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.top, AppSpacing.md)
            .padding(.bottom, AppSpacing.md)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var optionalSourceField: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(L10n.createAppreciationSource)
                .font(AppFont.helper())
                .foregroundStyle(AppColor.textMuted)

            TextField(L10n.createAppreciationSourcePlaceholder, text: $appreciationSource, axis: .vertical)
                .font(AppFont.secondary())
                .lineLimit(1...3)
                .padding(AppSpacing.sm)
                .appInputSurface(isFocused: false)
        }
    }

    private var captureToolbar: some View {
        HStack(spacing: AppSpacing.sm) {
            captureToolButton(
                title: L10n.createScanShort,
                systemImage: "camera.viewfinder",
                accessibilityLabel: L10n.createScanExcerpt,
                emphasized: true,
                disabled: isRecognizingPhoto
            ) {
                openScanCapture()
            }

            captureToolButton(
                title: L10n.createPhotoShort,
                systemImage: "photo.on.rectangle",
                accessibilityLabel: L10n.createQuickPhoto,
                emphasized: false,
                disabled: isRecognizingPhoto
            ) {
                showPhotoLibrary = true
            }

            captureToolButton(
                title: L10n.createPasteShort,
                systemImage: "doc.on.clipboard",
                accessibilityLabel: L10n.createQuickPaste,
                emphasized: false,
                disabled: false
            ) {
                pasteFromClipboard()
            }

            Spacer(minLength: 0)
        }
        .opacity(isRecognizingPhoto ? 0.72 : 1)
    }

    private func captureToolButton(
        title: String,
        systemImage: String,
        accessibilityLabel: String,
        emphasized: Bool,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .medium))
                Text(title)
                    .font(AppFont.helper().weight(.semibold))
            }
            .foregroundStyle(emphasized ? Color.white : AppColor.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                emphasized
                    ? AppColor.accentStrong
                    : Color.clear,
                in: Capsule()
            )
            .overlay {
                if !emphasized {
                    Capsule()
                        .strokeBorder(AppColor.border.opacity(0.9), lineWidth: 1)
                }
            }
        }
        .buttonStyle(SoftPressButtonStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.55 : 1)
        .accessibilityLabel(accessibilityLabel)
    }

    private func openScanCapture() {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            showCamera = true
        } else {
            showPhotoLibrary = true
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
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil,
                        from: nil,
                        for: nil
                    )
                }
            }

            switch sourceMode {
            case .edit:
                sourceEditSurface(minHeight: 88, showPlaceholder: false, placeholder: L10n.createPastePlaceholder)
            case .pick:
                PhraseTokenPicker(
                    sentence: trimmedSentence,
                    words: $words,
                    maxContentHeight: 220,
                    showsChrome: false,
                    onCommitPhrase: { phrase in
                        let result = appendCreateWord(phrase)
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

    private func sourceEditSurface(minHeight: CGFloat, showPlaceholder: Bool, placeholder: String) -> some View {
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
                Text(placeholder)
                    .font(AppFont.literaryQuote())
                    .foregroundStyle(AppColor.textMuted)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.top, AppSpacing.md + 2)
                    .allowsHitTesting(false)
            }
        }
        .appInputSurface(isFocused: isSourceFocused)
    }

    private func pasteFromClipboard() {
        #if canImport(UIKit)
        if let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            sentence = text
            sourceMode = .pick
            showToast(L10n.createQuickPaste)
        }
        #endif
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
    }

    private var generationQueueBanner: some View {
        Button {
            showGenerationQueue = true
        } label: {
            HStack(spacing: AppSpacing.sm) {
                if generationQueue.hasActiveJobs {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "checklist")
                }
                Text(generationQueue.hasActiveJobs
                     ? generationQueue.activeSummary
                     : L10n.createQueueTitle)
                    .font(AppFont.helper())
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(L10n.createQueueViewAction)
                    .font(AppFont.helper().weight(.semibold))
                    .foregroundStyle(AppColor.accent)
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .background(AppColor.surface)
        }
        .buttonStyle(.plain)
    }

    private var generateFooter: some View {
        VStack(spacing: AppSpacing.xs) {
            if !canGenerate {
                Text(L10n.createGenerateHintEmpty)
                    .font(AppFont.weak())
                    .foregroundStyle(AppColor.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppSpacing.md)
            }

            if canGenerate {
                if willGenerateAppreciation {
                    Text(L10n.createGenerateNoWordsHint)
                        .font(AppFont.weak())
                        .foregroundStyle(AppColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, AppSpacing.md)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Picker("", selection: $generationMode) {
                            ForEach(CardGenerationMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: generationMode) { _, mode in
                            CardGenerationPreferences.mode = mode
                        }

                        Text(generationMode.detail)
                            .font(AppFont.weak())
                            .foregroundStyle(AppColor.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, AppSpacing.md)
                }
            }

            Button {
                performGeneration()
            } label: {
                Text(L10n.createAIGenerate)
            }
            .buttonStyle(PrimaryButtonStyle(soft: true))
            .disabled(!canGenerate || isGeneratingAppreciation)
            .padding(.horizontal, AppSpacing.md)
        }
        .padding(.top, AppSpacing.sm)
        .padding(.bottom, AppSpacing.sm)
        .background(AppColor.pageBackground)
    }

    private func openShareDraftPreview() {
        guard let pendingDrafts = shareImport.pendingDrafts, !pendingDrafts.isEmpty else { return }
        drafts = pendingDrafts
        if selectedDeckID == nil {
            selectedDeckID = SharedDeckStore.resolvedSelectedDeckID()
        }
        shareImport.acknowledgeDrafts()
        showPreview = true
    }

    private func applyLongTextSuggestion(_ suggestion: LongTextSuggestion) {
        defer { pendingLongText = "" }

        switch suggestion {
        case .none, .keepSingleSentence:
            break
        case .splitIntoWords:
            let parsed = ImportTextAnalyzer.parse(sentence)
            if !parsed.prefilledWords.isEmpty {
                for word in parsed.prefilledWords {
                    _ = appendCreateWord(word)
                }
            } else {
                showToast(L10n.createLongTextSplitFallback)
            }
        }
    }

    @MainActor
    private func importCapturedImage(_ image: UIImage, successBanner: String) async {
        isRecognizingPhoto = true
        defer { isRecognizingPhoto = false }
        await recognizeImage(image, successBanner: successBanner)
    }

    @MainActor
    private func recognizeImage(_ image: UIImage, successBanner: String) async {
        do {
            let result = try await ImageOCRService.recognizeWithLiveTextFallback(in: image)
            let importSentence = result.preferredImportSentence
            guard !importSentence.isEmpty else {
                errorMessage = L10n.ocrEmpty
                return
            }

            // Highlight hits → word + containing sentence only (not the whole page).
            sentence = importSentence
            sourceHint = OCRContextExtractor.sourceHint(from: result.fullText)
            sourceImagePath = CardSourceImageStore.saveJPEG(image)
            if let hint = sourceHint?.trimmingCharacters(in: .whitespacesAndNewlines), !hint.isEmpty {
                appreciationSource = hint
            }
            if result.hasHighlightContext {
                words = []
            }

            var addedHighlights = 0
            for word in result.preferredImportWords {
                if case .added = appendCreateWord(word) {
                    addedHighlights += 1
                }
            }

            if result.hasHighlightContext {
                showToast(L10n.ocrHighlightContext(
                    addedHighlights,
                    result.importUnits.count
                ))
                sourceMode = .pick
            } else if addedHighlights > 0 {
                showToast(L10n.ocrHighlightDetected(addedHighlights))
                sourceMode = .pick
            } else {
                showToast(successBanner)
                sourceMode = .edit
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func appendSelectionToWords() {
        let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            wordFeedbackMessage = L10n.selectionEmpty
            wordFeedbackIsError = true
            return
        }

        let result = appendCreateWord(trimmed)
        if case .added = result {
            selectionClearNonce += 1
        } else if case .duplicate = result {
            selectionClearNonce += 1
        } else if case .existsInDeck = result {
            selectionClearNonce += 1
        }
        VocabularyWordFeedback.apply(result, message: &wordFeedbackMessage, isError: &wordFeedbackIsError)
        clearFeedbackLater()
    }

    @MainActor
    private func appendCreateWord(_ word: String) -> VocabularyWordAddResult {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        if wordExistsInSelectedDeck(trimmed) {
            return .existsInDeck(trimmed)
        }
        return VocabularyWords.append(trimmed, to: &words)
    }

    @MainActor
    private func wordExistsInSelectedDeck(_ word: String) -> Bool {
        guard !trimmedSentence.isEmpty else { return false }
        let deck = DeckService.resolvedDeck(id: selectedDeckID, in: modelContext)
        let units = KimiCardGenerator.makeGenerationUnits(sentence: trimmedSentence, words: [word])
        if units.isEmpty {
            return FlashCardDeduper.contains(
                word: word,
                sentence: trimmedSentence,
                in: deck,
                context: modelContext
            )
        }
        return units.contains {
            FlashCardDeduper.contains(
                word: word,
                sentence: $0.sentence,
                in: deck,
                context: modelContext
            )
        }
    }

    private func clearFeedbackLater() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            wordFeedbackMessage = nil
        }
    }

    private func showToast(_ message: String) {
        ToastCenter.shared.show(message)
    }

    private func applyShareImportIfNeeded() {
        guard let payload = shareImport.pendingPayload else { return }
        
        let hasSentence = !payload.sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        
        if !hasSentence, let imagePath = payload.sourceImagePath {
            Task { @MainActor in
                await processSharedImage(imagePath: imagePath)
            }
            shareImport.acknowledgeImport()
            return
        }
        
        sentence = payload.sentence
        if let word = payload.selectedWord {
            words = VocabularyWords.parse(from: word)
        } else {
            words = []
        }
        if let hint = payload.sourceHint?.trimmingCharacters(in: .whitespacesAndNewlines), !hint.isEmpty {
            sourceHint = hint
        }
        if let path = payload.sourceImagePath?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
            sourceImagePath = path
        }
        if !payload.bannerMessage.isEmpty {
            showToast(payload.bannerMessage)
        }
        sourceMode = words.isEmpty ? .edit : .pick
        shareImport.acknowledgeImport()
    }
    
    @MainActor
    private func processSharedImage(imagePath: String) async {
        guard let image = CardSourceImageStore.loadUIImage(relativePath: imagePath) else {
            errorMessage = L10n.ocrEmpty
            return
        }
        
        isRecognizingPhoto = true
        defer { isRecognizingPhoto = false }
        
        await recognizeImage(image, successBanner: L10n.importFromPhotoSuccess)
    }

    private func performGeneration() {
        if willGenerateAppreciation {
            Task { await generateAppreciationCard() }
        } else {
            enqueueGeneration()
        }
    }

    private func enqueueGeneration() {
        errorMessage = nil
        SharedDedupeSync.rebuild(in: modelContext)
        let deck = DeckService.resolvedDeck(id: selectedDeckID, in: modelContext)
        if selectedDeckID == nil {
            selectedDeckID = deck.id
        }

        do {
            _ = try generationQueue.enqueue(
                sentence: sentence,
                words: words,
                deckID: deck.id,
                deckName: deck.name,
                sourceHint: sourceHint,
                sourceImagePath: sourceImagePath
            )
            words = []
            showToast(L10n.createQueuedToast)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func generateAppreciationCard() async {
        guard willGenerateAppreciation else { return }
        isGeneratingAppreciation = true
        defer { isGeneratingAppreciation = false }

        errorMessage = nil
        let manualSource = appreciationSource.trimmingCharacters(in: .whitespacesAndNewlines)
        let ocrSource = sourceHint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedSource = manualSource.isEmpty
            ? (ocrSource.isEmpty ? nil : ocrSource)
            : manualSource

        let reflection = DailyReflection(
            sentence: trimmedSentence,
            translation: nil,
            source: resolvedSource,
            occasion: nil,
            isAI: true
        )

        do {
            var draft = try await LiteraryAppreciationGenerator.generate(from: reflection)
            if let path = sourceImagePath?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
                draft.sourceImagePath = path
            }

            let deck: Deck
            if let selectedDeckID {
                deck = DeckService.resolvedDeck(id: selectedDeckID, in: modelContext)
            } else {
                deck = DeckService.fetchOrCreateDailyReflectionDeck(in: modelContext)
            }
            selectedDeckID = deck.id
            drafts = [draft]
            showPreview = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct CreateCardsAlertsModifier: ViewModifier {
    @Binding var errorMessage: String?

    func body(content: Content) -> some View {
        content.alert(L10n.generateFailedTitle, isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(L10n.ok, role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }
}

private struct CreateCardsLifecycleModifier: ViewModifier {
    @Binding var sentence: String
    @Binding var pendingLongText: String
    @Binding var showLongTextPrompt: Bool
    @Binding var showPreview: Bool
    @Binding var drafts: [GeneratedCardDraft]

    let shareImport: ShareImportCoordinator
    let onAppearImport: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear {
                shareImport.refreshAll()
                onAppearImport()
            }
            .onChange(of: shareImport.pendingPayload) { _, _ in
                onAppearImport()
            }
            .onChange(of: showPreview) { _, isShowing in
                guard !isShowing else { return }
                DispatchQueue.main.async {
                    drafts.removeAll()
                }
            }
            .onChange(of: sentence) { oldValue, newValue in
                guard oldValue.count <= 800, newValue.count > 800, pendingLongText != newValue else { return }
                pendingLongText = newValue
                showLongTextPrompt = true
            }
    }
}

#Preview {
    CreateCardsView()
        .environmentObject(ShareImportCoordinator())
}

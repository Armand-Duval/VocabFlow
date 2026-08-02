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
    @State private var isGenerating = false
    @State private var showPreview = false
    @State private var errorMessage: String?
    @State private var importBannerMessage: String?
    @State private var selectedText = ""
    @State private var selectionClearNonce = 0
    @State private var wordFeedbackMessage: String?
    @State private var wordFeedbackIsError = false
    @State private var isRecognizingPhoto = false
    @State private var showPhotoLibrary = false
    @State private var showCamera = false
    @State private var showLongTextPrompt = false
    @State private var pendingLongText = ""
    @State private var longTextChoiceMade = false
    @State private var isManualEditing = false
    @State private var sourceHint: String?
    @State private var todayCaptureTip: String?
    @State private var isSourceFocused = false

    private var trimmedSentence: String {
        sentence.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canGenerate: Bool {
        !trimmedSentence.isEmpty && !words.isEmpty
    }

    private var generateDisabledHint: String? {
        guard !canGenerate, !isGenerating else { return nil }
        if trimmedSentence.isEmpty && words.isEmpty {
            return L10n.createGenerateNeedBoth
        }
        if trimmedSentence.isEmpty {
            return L10n.createGenerateNeedSentence
        }
        return L10n.createGenerateNeedWords
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
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            AppTab.requestSettings()
                        } label: {
                            AppIcon.symbol("gearshape")
                        }
                        .accessibilityLabel(L10n.settingsTitle)
                    }
                }
                .dismissKeyboardOnScroll()
                .keyboardDoneButton()
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    generateFooter
                }
                .loadingOverlay(isPresented: isGenerating, message: L10n.generating)
                .loadingOverlay(isPresented: isRecognizingPhoto, message: L10n.recognizingPhoto)
                .navigationDestination(isPresented: $showPreview) {
                    CardPreviewView(drafts: drafts, selectedDeckID: $selectedDeckID) {
                        showPreview = false
                    }
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
                .onAppear { refreshCaptureTip() }
                .onChange(of: showPreview) { _, isShowing in
                    if !isShowing { refreshCaptureTip() }
                }
                .onReceive(NotificationCenter.default.publisher(for: .libraryCatalogDidChange)) { _ in
                    refreshCaptureTip()
                }
        }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                if hasPendingDrafts, let pendingDrafts = shareImport.pendingDrafts {
                    PendingCardsBannerView(
                        title: L10n.createPendingImportTitle,
                        subtitle: L10n.createPendingDraftsSubtitle(pendingDrafts.count),
                        systemImage: "sparkles.rectangle.stack.fill",
                        actionTitle: L10n.createPendingAction,
                        action: openShareDraftPreview
                    )
                } else if let importBannerMessage {
                    PendingCardsBannerView(
                        title: L10n.createPendingImportTitle,
                        subtitle: importBannerMessage,
                        systemImage: "arrow.down.doc.fill",
                        onDismiss: { self.importBannerMessage = nil }
                    )
                }

                if let todayCaptureTip {
                    Text(todayCaptureTip)
                        .font(AppFont.helper())
                        .foregroundStyle(AppColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(todayCaptureTip)
                }

                sourceEditor

                if !selectedText.isEmpty {
                    SelectionActionBar(selectedText: selectedText, action: appendSelectionToWords)
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
                    .padding(.vertical, AppSpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appInputSurface(isFocused: false)
                    .appSoftShadow()

                wordsCard
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.top, AppSpacing.md)
            .padding(.bottom, AppSpacing.md)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var sourceEditor: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.xs) {
                createImportTool(
                    systemImage: "photo.on.rectangle",
                    label: L10n.createQuickPhoto,
                    disabled: isRecognizingPhoto
                ) {
                    showPhotoLibrary = true
                }

                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    createImportTool(
                        systemImage: "camera",
                        label: L10n.createQuickCamera,
                        disabled: isRecognizingPhoto
                    ) {
                        showCamera = true
                    }
                }

                createImportTool(
                    systemImage: "doc.on.clipboard",
                    label: L10n.createQuickPaste,
                    disabled: false
                ) {
                    pasteFromClipboard()
                }

                Spacer(minLength: 0)
            }

            ZStack(alignment: .topLeading) {
                SelectableTextEditor(
                    text: $sentence,
                    selectedText: $selectedText,
                    selectionClearNonce: $selectionClearNonce,
                    isFocused: $isSourceFocused,
                    onAddToVocabulary: appendSelectionToWords
                )
                .frame(minHeight: 180)
                .padding(AppSpacing.sm)

                if sentence.isEmpty {
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
    }

    private func createImportTool(
        systemImage: String,
        label: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(disabled ? AppColor.textMuted : AppColor.textSecondary)
                .frame(width: 36, height: 36)
                .background(
                    AppColor.surfaceMuted,
                    in: RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous)
                )
                .appSoftShadow()
        }
        .buttonStyle(SoftPressButtonStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.55 : 1)
        .accessibilityLabel(label)
    }

    private func pasteFromClipboard() {
        #if canImport(UIKit)
        if let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            sentence = text
            importBannerMessage = L10n.createQuickPaste
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
                    .transition(.opacity)
            }

            Button(action: generateCards) {
                HStack(spacing: AppSpacing.xs) {
                    if isGenerating {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(isGenerating ? L10n.generating : L10n.createAIGenerate)
                }
            }
            .buttonStyle(PrimaryButtonStyle(prominent: true))
            .disabled(isGenerating || !canGenerate)
            .padding(.horizontal, AppSpacing.md)
        }
        .padding(.top, AppSpacing.sm)
        .padding(.bottom, AppSpacing.sm)
        .background(AppColor.pageBackground)
        .animation(.easeInOut(duration: 0.15), value: generateDisabledHint)
    }

    private func openShareDraftPreview() {
        guard let pendingDrafts = shareImport.pendingDrafts, !pendingDrafts.isEmpty else { return }
        drafts = pendingDrafts
        if selectedDeckID == nil {
            selectedDeckID = SharedDeckStore.resolvedSelectedDeckID()
        }
        shareImport.acknowledgeDrafts()
        importBannerMessage = nil
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
            let result = try await ImageOCRService.recognize(in: image)
            let importSentence = result.preferredImportSentence
            guard !importSentence.isEmpty else {
                errorMessage = L10n.ocrEmpty
                return
            }

            // Highlight hits → word + containing sentence only (not the whole page).
            sentence = importSentence
            sourceHint = OCRContextExtractor.sourceHint(from: result.fullText)
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
                let message = L10n.ocrHighlightContext(
                    addedHighlights,
                    result.importUnits.count
                )
                importBannerMessage = message
                showToast(message)
            } else if addedHighlights > 0 {
                let message = L10n.ocrHighlightDetected(addedHighlights)
                importBannerMessage = message
                showToast(message)
            } else {
                importBannerMessage = successBanner
                showToast(successBanner)
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
        return FlashCardDeduper.contains(
            word: word,
            sentence: trimmedSentence,
            in: deck,
            context: modelContext
        )
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
        sentence = payload.sentence
        if let word = payload.selectedWord {
            words = VocabularyWords.parse(from: word)
        }
        importBannerMessage = payload.bannerMessage
        shareImport.acknowledgeImport()
    }

    private func refreshCaptureTip() {
        if let summary = CaptureStatsStore.todaySummary(in: modelContext),
           summary.uniqueWords > 0 || summary.uniqueSentences > 0 {
            todayCaptureTip = L10n.createCaptureToday(summary.uniqueWords, summary.uniqueSentences)
        } else {
            todayCaptureTip = nil
        }
    }

    private func generateCards() {
        errorMessage = nil
        isGenerating = true

        Task {
            do {
                let prep = await MainActor.run { () -> (deckID: UUID, deckName: String?, kept: [String], skipped: Int) in
                    SharedDedupeSync.rebuild(in: modelContext)
                    let deck = DeckService.resolvedDeck(id: selectedDeckID, in: modelContext)
                    if selectedDeckID == nil {
                        selectedDeckID = deck.id
                    }
                    let filtered = SharedDedupeIndex.filterNewWords(
                        words,
                        deckID: deck.id,
                        sentence: sentence
                    )
                    return (deck.id, deck.name, filtered.kept, filtered.skippedCount)
                }

                guard !prep.kept.isEmpty else {
                    await MainActor.run {
                        isGenerating = false
                        errorMessage = L10n.createGenerateAllDuplicates
                    }
                    return
                }

                let generated = try await KimiCardGenerator.generate(
                    sentence: sentence,
                    words: prep.kept,
                    sourceHint: sourceHint,
                    deckName: prep.deckName,
                    skipExistingInDeckID: prep.deckID
                )

                await MainActor.run {
                    isGenerating = false
                    if generated.isEmpty {
                        errorMessage = L10n.generateEmptyError
                    } else {
                        drafts = generated
                        showPreview = true
                        if prep.skipped > 0 {
                            showToast(L10n.createGenerateSuccessSkipped(generated.count, prep.skipped))
                        } else {
                            showToast(L10n.createGenerateSuccess(generated.count))
                        }
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

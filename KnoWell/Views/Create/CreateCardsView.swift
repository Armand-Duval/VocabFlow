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

    private var trimmedSentence: String {
        sentence.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canGenerate: Bool {
        !trimmedSentence.isEmpty && !words.isEmpty
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
        }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: AppSpacing.sm) {
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

                quickCaptureRow

                sourceEditor

                if !selectedText.isEmpty {
                    SelectionActionBar(selectedText: selectedText, action: appendSelectionToWords)
                }

                if isRecognizingPhoto {
                    HStack(spacing: AppSpacing.xs) {
                        ProgressView()
                        Text(L10n.recognizingPhoto)
                            .font(AppFont.caption())
                            .foregroundStyle(AppColor.textTertiary)
                    }
                }

                compactDeckRow

                wordsCard
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.top, AppSpacing.sm)
            .padding(.bottom, AppSpacing.md)
        }
    }

    private var quickCaptureRow: some View {
        HStack(spacing: 6) {
            Text(L10n.createQuickCaptureTitle)
                .font(AppFont.weak())
                .foregroundStyle(AppColor.textTertiary)

            Spacer(minLength: AppSpacing.sm)

            TextLinkAction(title: L10n.createQuickPhoto) {
                showPhotoLibrary = true
            }
            .disabled(isRecognizingPhoto)
            .opacity(isRecognizingPhoto ? 0.45 : 1)

            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Text("·")
                    .font(AppFont.weak())
                    .foregroundStyle(AppColor.textTertiary.opacity(0.45))

                TextLinkAction(title: L10n.createQuickCamera) {
                    showCamera = true
                }
                .disabled(isRecognizingPhoto)
                .opacity(isRecognizingPhoto ? 0.45 : 1)
            }

            Text("·")
                .font(AppFont.weak())
                .foregroundStyle(AppColor.textTertiary.opacity(0.45))

            TextLinkAction(title: L10n.createQuickPaste) {
                pasteFromClipboard()
            }
        }
    }

    private var sourceEditor: some View {
        ZStack(alignment: .topLeading) {
            SelectableTextEditor(
                text: $sentence,
                selectedText: $selectedText,
                selectionClearNonce: $selectionClearNonce,
                onAddToVocabulary: appendSelectionToWords
            )
            .frame(minHeight: 160)
            .padding(AppSpacing.sm)
            .background(
                AppColor.surfaceMuted,
                in: RoundedRectangle(cornerRadius: AppRadius.input, style: .continuous)
            )

            if sentence.isEmpty {
                Text(L10n.createPastePlaceholder)
                    .font(AppFont.secondary())
                    .foregroundStyle(AppColor.textTertiary)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.top, AppSpacing.md)
                    .allowsHitTesting(false)
            }
        }
    }

    private var compactDeckRow: some View {
        HStack {
            CreateDeckPickerCard(selectedDeckID: $selectedDeckID)
            Spacer(minLength: 0)
        }
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
                .font(AppFont.weak())
                .foregroundStyle(AppColor.textTertiary)

            VocabularyWordsEditor(
                words: $words,
                feedbackMessage: $wordFeedbackMessage,
                feedbackIsError: $wordFeedbackIsError
            )
        }
        .padding(AppSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            AppColor.surface,
            in: RoundedRectangle(cornerRadius: AppRadius.input, style: .continuous)
        )
    }

    private var generateFooter: some View {
        Button(action: generateCards) {
            HStack(spacing: AppSpacing.xs) {
                if isGenerating {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "sparkles")
                }
                Text(L10n.createAIGenerate)
            }
        }
        .buttonStyle(PrimaryButtonStyle(prominent: true))
        .disabled(isGenerating || !canGenerate)
        .padding(.horizontal, AppSpacing.md)
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
                    _ = VocabularyWords.append(word, to: &words)
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
                if case .added = VocabularyWords.append(word, to: &words) {
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

    private func generateCards() {
        errorMessage = nil
        isGenerating = true

        Task {
            do {
                let generated = try await KimiCardGenerator.generate(
                    sentence: sentence,
                    words: words,
                    sourceHint: sourceHint
                )

                await MainActor.run {
                    isGenerating = false
                    if generated.isEmpty {
                        errorMessage = L10n.generateEmptyError
                    } else {
                        drafts = generated
                        showPreview = true
                        showToast(L10n.createGenerateSuccess(generated.count))
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

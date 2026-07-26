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

    private var hasPendingImportBanner: Bool {
        importBannerMessage != nil
    }

    var body: some View {
        NavigationStack {
            formContent
                .navigationTitle(L10n.createTitle)
                .navigationBarTitleDisplayMode(.large)
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
                .confirmationDialog(
                    L10n.createLongTextTitle,
                    isPresented: $showLongTextPrompt,
                    titleVisibility: .visible
                ) {
                    Button(L10n.createLongTextKeepSentence) {
                        applyLongTextSuggestion(.keepSingleSentence)
                    }
                    Button(L10n.createLongTextSplitWords) {
                        applyLongTextSuggestion(.splitIntoWords)
                    }
                    Button(L10n.cancel, role: .cancel) {
                        pendingLongText = ""
                    }
                } message: {
                    Text(L10n.createLongTextMessage)
                }
        }
    }

    private var formContent: some View {
        Form {
            Section {
                quickActionsSection
            }
            .listRowInsets(EdgeInsets(top: AppSpacing.sm, leading: AppSpacing.md, bottom: AppSpacing.sm, trailing: AppSpacing.md))
            .listRowBackground(Color.clear)

            if hasPendingDrafts, let pendingDrafts = shareImport.pendingDrafts {
                Section {
                    PendingCardsBannerView(
                        title: L10n.createPendingImportTitle,
                        subtitle: L10n.createPendingDraftsSubtitle(pendingDrafts.count),
                        systemImage: "sparkles.rectangle.stack.fill",
                        actionTitle: L10n.createPendingAction,
                        action: openShareDraftPreview
                    )
                }
                .listRowInsets(EdgeInsets(top: 0, leading: AppSpacing.md, bottom: AppSpacing.sm, trailing: AppSpacing.md))
                .listRowBackground(Color.clear)
            } else if let importBannerMessage {
                Section {
                    PendingCardsBannerView(
                        title: L10n.createPendingImportTitle,
                        subtitle: importBannerMessage,
                        systemImage: "arrow.down.doc.fill",
                        onDismiss: { self.importBannerMessage = nil }
                    )
                }
                .listRowInsets(EdgeInsets(top: 0, leading: AppSpacing.md, bottom: AppSpacing.sm, trailing: AppSpacing.md))
                .listRowBackground(Color.clear)
            }

            sourceSection
            wordsSection
            DeckPickerSection(selectedDeckID: $selectedDeckID)
        }
        .appFormSectionSpacing()
    }

    private var quickActionsSection: some View {
        HStack(spacing: AppSpacing.sm) {
            QuickActionChip(
                systemImage: "photo.on.rectangle",
                title: L10n.createQuickPhoto,
                isLoading: isRecognizingPhoto,
                isDisabled: isRecognizingPhoto
            ) {
                showPhotoLibrary = true
            }
            .accessibilityLabel(L10n.importFromPhoto)

            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                QuickActionChip(
                    systemImage: "camera.fill",
                    title: L10n.createQuickCamera,
                    isLoading: isRecognizingPhoto,
                    isDisabled: isRecognizingPhoto
                ) {
                    showCamera = true
                }
                .accessibilityLabel(L10n.importFromCamera)
            }

            QuickActionChip(
                systemImage: "tray.and.arrow.down.fill",
                title: L10n.createQuickPending,
                isHighlighted: hasPendingDrafts || hasPendingImportBanner
            ) {
                if hasPendingDrafts {
                    openShareDraftPreview()
                }
            }
            .disabled(!hasPendingDrafts)
            .accessibilityLabel(L10n.createPendingImportTitle)
        }
    }

    private var sourceSection: some View {
        Section {
            ZStack(alignment: .topLeading) {
                SelectableTextEditor(
                    text: $sentence,
                    selectedText: $selectedText,
                    selectionClearNonce: $selectionClearNonce,
                    onAddToVocabulary: appendSelectionToWords
                )

                if sentence.isEmpty {
                    Text(L10n.createSourceEmptyHint)
                        .foregroundStyle(.secondary)
                        .font(AppFont.helper())
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                }
            }

            if !selectedText.isEmpty {
                SelectionActionBar(selectedText: selectedText, action: appendSelectionToWords)
            }
        } header: {
            HStack {
                Text(L10n.sourceText)
                Spacer()
                if !sentence.isEmpty {
                    Text(L10n.createCharCount(sentence.count))
                        .font(AppFont.caption())
                        .foregroundStyle(.secondary)
                    Button(L10n.clear) {
                        sentence = ""
                        selectedText = ""
                    }
                    .font(AppFont.caption())
                }
            }
        }
    }

    private var wordsSection: some View {
        Section {
            VocabularyWordsEditor(
                words: $words,
                feedbackMessage: $wordFeedbackMessage,
                feedbackIsError: $wordFeedbackIsError
            )
        } header: {
            Text(L10n.wordsSection)
        }
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
                Text(L10n.generateCardsShort)
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(isGenerating || !canGenerate)
        .padding(.horizontal, AppSpacing.md)
        .padding(.top, AppSpacing.sm)
        .padding(.bottom, AppSpacing.xs)
        .background(.bar)
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
            let text = try await ImageOCRService.recognizeText(in: image)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                errorMessage = L10n.ocrEmpty
                return
            }
            sentence = text
            importBannerMessage = successBanner
            showToast(successBanner)
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
                let generated = try await KimiCardGenerator.generate(sentence: sentence, words: words)

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

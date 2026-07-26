import SwiftUI
import PhotosUI
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
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isRecognizingPhoto = false
    @State private var showCamera = false
    @State private var showLongTextPrompt = false
    @State private var pendingLongText = ""

    private var trimmedSentence: String {
        sentence.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canGenerate: Bool {
        !trimmedSentence.isEmpty && !words.isEmpty
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
                    selectedPhotoItem: $selectedPhotoItem,
                    shareImport: shareImport,
                    onAppearImport: applyShareImportIfNeeded,
                    onPhotoSelected: { item in
                        Task { await importPhoto(item) }
                    }
                ))
                .sheet(isPresented: $showCamera) {
                    CameraImagePicker { image in
                        Task { await importCapturedImage(image) }
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
            if let importBannerMessage {
                Section {
                    ImportBannerView(
                        message: importBannerMessage,
                        systemImage: "arrow.down.doc"
                    )
                }
            }

            sourceSection
            wordsSection
                DeckPickerSection(selectedDeckID: $selectedDeckID)
            }
            .appFormSectionSpacing()
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

            importActionsRow

            if isRecognizingPhoto {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(L10n.recognizingPhoto)
                        .font(AppFont.caption())
                        .foregroundStyle(.secondary)
                }
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
        } footer: {
            if sentence.isEmpty {
                Text(L10n.createSourceFooterHint)
            } else if sentence.count > 800 {
                Text(L10n.createSourceLongHint)
            }
        }
    }

    private var importActionsRow: some View {
        HStack(spacing: AppSpacing.md) {
            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                AppIcon.symbol("photo.on.rectangle")
                    .foregroundStyle(AppColor.accent)
                    .frame(width: 44, height: 44)
                    .background(AppColor.accentBackground(0.10), in: RoundedRectangle(cornerRadius: AppRadius.button))
            }
            .disabled(isRecognizingPhoto)
            .accessibilityLabel(L10n.importFromPhoto)

            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    showCamera = true
                } label: {
                    AppIcon.symbol("camera")
                        .foregroundStyle(AppColor.accent)
                        .frame(width: 44, height: 44)
                        .background(AppColor.accentBackground(0.10), in: RoundedRectangle(cornerRadius: AppRadius.button))
                }
                .disabled(isRecognizingPhoto)
                .accessibilityLabel(L10n.importFromCamera)
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
        } footer: {
            if words.isEmpty {
                Text(L10n.createWordsEmptyHint)
            }
        }
    }

    private var generateFooter: some View {
        VStack(spacing: AppSpacing.xs) {
            if !canGenerate {
                Text(L10n.createGenerateHint)
                    .font(AppFont.helper())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: generateCards) {
                HStack(spacing: AppSpacing.xs) {
                    if isGenerating {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(L10n.generateCards)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isGenerating || !canGenerate)
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.top, AppSpacing.sm)
        .padding(.bottom, AppSpacing.xs)
        .background(.bar)
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

    private func importPhoto(_ item: PhotosPickerItem) async {
        isRecognizingPhoto = true
        defer {
            isRecognizingPhoto = false
            selectedPhotoItem = nil
        }

        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            errorMessage = L10n.ocrFailed
            return
        }

        await recognizeImage(image, successBanner: L10n.importFromPhotoSuccess)
    }

    @MainActor
    private func importCapturedImage(_ image: UIImage) async {
        isRecognizingPhoto = true
        defer { isRecognizingPhoto = false }
        await recognizeImage(image, successBanner: L10n.importFromCameraSuccess)
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
    @Binding var selectedPhotoItem: PhotosPickerItem?

    let shareImport: ShareImportCoordinator
    let onAppearImport: () -> Void
    let onPhotoSelected: (PhotosPickerItem) -> Void

    func body(content: Content) -> some View {
        content
            .onAppear(perform: onAppearImport)
            .onChange(of: shareImport.pendingPayload) { _, _ in
                onAppearImport()
            }
            .onChange(of: showPreview) { _, isShowing in
                guard !isShowing else { return }
                DispatchQueue.main.async {
                    drafts.removeAll()
                }
            }
            .onChange(of: selectedPhotoItem) { _, item in
                guard let item else { return }
                onPhotoSelected(item)
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

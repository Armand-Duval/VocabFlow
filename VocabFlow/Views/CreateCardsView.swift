import SwiftUI
import PhotosUI
import UIKit

struct CreateCardsView: View {
    @EnvironmentObject private var shareImport: ShareImportCoordinator
    @State private var sentence = ""
    @State private var words: [String] = []
    @State private var drafts: [GeneratedCardDraft] = []
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

    var body: some View {
        NavigationStack {
            Form {
                if let importBannerMessage {
                    Section {
                        ImportBannerView(
                            message: importBannerMessage,
                            systemImage: "arrow.down.doc"
                        )
                    }
                }

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

                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label(L10n.importFromPhoto, systemImage: "photo.on.rectangle")
                    }
                    .disabled(isRecognizingPhoto)

                    if isRecognizingPhoto {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(L10n.recognizingPhoto)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
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
            .navigationBarTitleDisplayMode(.large)
            .dismissKeyboardOnScroll()
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        generateCards()
                    } label: {
                        if isGenerating {
                            ProgressView()
                        } else {
                            Image(systemName: "sparkles")
                        }
                    }
                    .disabled(isGenerating || sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || words.isEmpty)
                    .accessibilityLabel(L10n.generateCards)
                }
            }
            .navigationDestination(isPresented: $showPreview) {
                CardPreviewView(drafts: drafts) {
                    showPreview = false
                }
            }
            .onChange(of: showPreview) { _, isShowing in
                guard !isShowing else { return }
                DispatchQueue.main.async {
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
            .onChange(of: selectedPhotoItem) { _, item in
                guard let item else { return }
                Task {
                    await importPhoto(item)
                }
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

        do {
            let text = try await ImageOCRService.recognizeText(in: image)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                errorMessage = L10n.ocrEmpty
                return
            }
            sentence = text
            importBannerMessage = L10n.importFromPhotoSuccess
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

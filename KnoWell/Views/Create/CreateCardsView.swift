import SwiftUI
import UIKit

struct CreateCardsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(CloudAIQuotaStore.self) private var aiQuota
    @EnvironmentObject private var shareImport: ShareImportCoordinator
    @State private var sentence = ""
    @State private var words: [String] = []
    @State private var drafts: [GeneratedCardDraft] = []
    @State private var selectedDeckID: UUID?
    @ObservedObject private var generationQueue = CardGenerationQueue.shared
    @State private var showPreview = false
    /// User left confirmation with cards still waiting — don't force the sheet back open.
    @State private var deferredPreview = false
    @State private var showGenerationQueue = false
    @State private var errorMessage: String?
    @State private var selectedText = ""
    @State private var selectionClearNonce = 0
    @State private var wordFeedbackMessage: String?
    @State private var wordFeedbackIsError = false
    @State private var isPreparingCapture = false
    @State private var isRunningOCR = false
    @State private var isGeneratingAppreciation = false
    @State private var generationMode: CardGenerationMode = CardGenerationPreferences.mode
    @State private var appreciationSource = ""
    @State private var showPhotoLibrary = false
    @State private var showCamera = false
    @State private var liveTextDraft: LiveTextScanDraft?
    @State private var isManualEditing = false
    @State private var sourceHint: String?
    @State private var sourceImagePath: String?
    @State private var isSourceFocused = false
    @State private var sourceMode: SourceWorkspaceMode = .edit
    /// Empty create page only shows scan / album / paste until there is content.

    private var trimmedSentence: String {
        sentence.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var showsCreateWorkspace: Bool {
        !trimmedSentence.isEmpty || !words.isEmpty
    }

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
                    if showsCreateWorkspace {
                        generateFooter
                    }
                }
                .loadingOverlay(
                    isPresented: isRunningOCR || isGeneratingAppreciation,
                    message: isGeneratingAppreciation ? L10n.createAppreciationGenerating : L10n.recognizingPhoto
                )
                .navigationDestination(isPresented: $showPreview) {
                    CardPreviewView(selectedDeckID: $selectedDeckID) {
                        deferredPreview = generationQueue.pendingTriageCardCount > 0
                        showPreview = false
                    }
                }
                .sheet(isPresented: $showGenerationQueue) {
                    CardGenerationQueueView(queue: generationQueue)
                }
                .onChange(of: generationQueue.pendingTriageCardCount) { oldCount, count in
                    guard count > oldCount else { return }
                    deferredPreview = false
                    if let deckID = generationQueue.readyPreview?.deckID {
                        selectedDeckID = deckID
                    }
                    showPreview = true
                }
                .onChange(of: shareImport.pendingDrafts) { _, _ in
                    ingestShareDraftsIfNeeded()
                }
                .onChange(of: shareImport.pendingInbox) { _, _ in
                    Task { await applyShareInboxIfNeeded() }
                }
                .task {
                    await aiQuota.refresh()
                }
                .onAppear {
                    ingestShareDraftsIfNeeded()
                    Task { await applyShareInboxIfNeeded() }
                    guard !deferredPreview, generationQueue.readyPreview != nil else { return }
                    selectedDeckID = generationQueue.readyPreview?.deckID ?? selectedDeckID
                    showPreview = true
                }
                .modifier(CreateCardsAlertsModifier(errorMessage: $errorMessage))
                .modifier(CreateCardsLifecycleModifier(
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
                .fullScreenCover(item: $liveTextDraft) { draft in
                    LiveTextScanSheet(image: draft.image, analysis: draft.analysis) { result in
                        applyLiveTextResult(result, image: draft.image, banner: draft.successBanner)
                    }
                }
                .onChange(of: isSourceFocused) { _, focused in
                    if !focused, trimmedSentence.isEmpty, words.isEmpty {
                        isManualEditing = false
                        selectedText = ""
                        sourceMode = .edit
                    }
                }
        }
    }

    private var scrollContent: some View {
        Group {
            if showsCreateWorkspace {
                workspaceScroll
            } else {
                emptyCapturePage
            }
        }
    }

    private var workspaceScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                pendingBanners

                captureToolbar

                sourceWorkspace

                if sourceMode == .edit, !selectedText.isEmpty {
                    SelectionActionBar(selectedText: selectedText, action: appendSelectionToWords)
                }

                if willGenerateAppreciation {
                    optionalSourceField
                }

                CreateDeckPickerCard(selectedDeckID: $selectedDeckID)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, AppSpacing.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appInputSurface(isFocused: false)

                wordsCard
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.top, AppSpacing.sm)
            .padding(.bottom, AppSpacing.md)
        }
        .appVerticalBounce()
    }

    @ViewBuilder
    private var pendingBanners: some View {
        if hasPendingDrafts, let pendingDrafts = shareImport.pendingDrafts {
            PendingCardsBannerView(
                title: L10n.createPendingImportTitle,
                subtitle: L10n.createPendingDraftsSubtitle(pendingDrafts.count),
                systemImage: "sparkles.rectangle.stack.fill",
                actionTitle: L10n.createPendingAction,
                action: ingestShareDraftsIfNeeded
            )
        } else if !showPreview, generationQueue.pendingTriageCardCount > 0 {
            PendingCardsBannerView(
                title: L10n.createPendingImportTitle,
                subtitle: L10n.createPendingDraftsSubtitle(generationQueue.pendingTriageCardCount),
                systemImage: "checklist",
                actionTitle: L10n.createPendingAction,
                action: {
                    deferredPreview = false
                    selectedDeckID = generationQueue.readyPreview?.deckID ?? selectedDeckID
                    showPreview = true
                }
            )
        }
    }

    private var emptyCapturePage: some View {
        VStack(spacing: 0) {
            pendingBanners
                .padding(.horizontal, AppSpacing.md)
                .padding(.top, AppSpacing.sm)

            Spacer(minLength: 24)

            HStack(spacing: AppSpacing.sm) {
                emptyCaptureTile(
                    title: L10n.createScanShort,
                    systemImage: "camera.viewfinder",
                    accessibilityLabel: L10n.createScanExcerpt,
                    filledIcon: true,
                    disabled: isPreparingCapture || isRunningOCR
                ) {
                    openScanCapture()
                }

                emptyCaptureTile(
                    title: L10n.createPhotoShort,
                    systemImage: "photo.on.rectangle",
                    accessibilityLabel: L10n.createQuickPhoto,
                    filledIcon: false,
                    disabled: isPreparingCapture || isRunningOCR
                ) {
                    showPhotoLibrary = true
                }

                emptyCaptureTile(
                    title: L10n.createPasteShort,
                    systemImage: "doc.on.clipboard",
                    accessibilityLabel: L10n.createQuickPaste,
                    filledIcon: false,
                    disabled: false
                ) {
                    pasteFromClipboard()
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .opacity((isPreparingCapture || isRunningOCR) ? 0.72 : 1)

            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyCaptureTile(
        title: String,
        systemImage: String,
        accessibilityLabel: String,
        filledIcon: Bool,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(filledIcon ? AppColor.accentStrong : AppColor.accent.opacity(0.12))
                        .frame(width: 56, height: 56)
                    Image(systemName: systemImage)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(filledIcon ? Color.white : AppColor.accent)
                }

                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background(AppColor.surface, in: RoundedRectangle(cornerRadius: AppRadius.sheet, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.sheet, style: .continuous)
                    .strokeBorder(AppColor.border, lineWidth: 1)
            }
            .appSoftShadow()
        }
        .buttonStyle(SoftPressButtonStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.55 : 1)
        .accessibilityLabel(accessibilityLabel)
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
                disabled: isPreparingCapture || isRunningOCR
            ) {
                openScanCapture()
            }

            captureToolButton(
                title: L10n.createPhotoShort,
                systemImage: "photo.on.rectangle",
                accessibilityLabel: L10n.createQuickPhoto,
                emphasized: false,
                disabled: isPreparingCapture || isRunningOCR
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
        .opacity((isPreparingCapture || isRunningOCR) ? 0.72 : 1)
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
                sourceEditSurface(
                    minHeight: 88,
                    showPlaceholder: trimmedSentence.isEmpty,
                    placeholder: L10n.createPastePlaceholder
                )
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
            isManualEditing = true
            sourceMode = .pick
            showToast(L10n.createQuickPaste)
        } else {
            showToast(L10n.createPasteEmpty)
        }
        #endif
    }

    private func resetCreateWorkspace() {
        sentence = ""
        words = []
        selectedText = ""
        selectionClearNonce += 1
        isManualEditing = false
        isSourceFocused = false
        sourceMode = .edit
        sourceHint = nil
        sourceImagePath = nil
        appreciationSource = ""
        wordFeedbackMessage = nil
        wordFeedbackIsError = false
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

    private var isCloudQuotaExhausted: Bool {
        APISettings.usesCloudProxy && (aiQuota.snapshot?.isExhausted == true)
    }

    private var cloudQuotaNeeded: Int {
        willGenerateAppreciation ? 1 : max(words.count, 1)
    }

    private var isCloudQuotaInsufficient: Bool {
        guard APISettings.usesCloudProxy, let snapshot = aiQuota.snapshot else { return false }
        return snapshot.blocks(needed: cloudQuotaNeeded)
    }

    private var generateFooter: some View {
        VStack(spacing: AppSpacing.xs) {
            if APISettings.usesCloudProxy, let snapshot = aiQuota.snapshot {
                Text(
                    snapshot.isExhausted
                        ? L10n.cloudQuotaExhausted
                        : L10n.cloudQuotaRemaining(snapshot.remaining, snapshot.limit)
                )
                .font(AppFont.weak())
                .foregroundStyle(snapshot.isExhausted ? AppColor.warning : AppColor.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AppSpacing.md)

                if isCloudQuotaInsufficient, !snapshot.isExhausted, canGenerate {
                    Text(L10n.cloudQuotaInsufficient(cloudQuotaNeeded, snapshot.remaining))
                        .font(AppFont.weak())
                        .foregroundStyle(AppColor.warning)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, AppSpacing.md)
                }
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
            .disabled(!canGenerate || isGeneratingAppreciation || isCloudQuotaExhausted || isCloudQuotaInsufficient)
            .padding(.horizontal, AppSpacing.md)
        }
        .padding(.top, AppSpacing.sm)
        .padding(.bottom, AppSpacing.sm)
        .background {
            AppColor.pageBackground
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(AppColor.borderSubtle)
                        .frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func ingestShareDraftsIfNeeded() {
        guard let pendingDrafts = shareImport.pendingDrafts, !pendingDrafts.isEmpty else { return }
        let deck = DeckService.resolvedDeck(id: selectedDeckID, in: modelContext)
        selectedDeckID = deck.id
        generationQueue.enqueueTriage(drafts: pendingDrafts, deckID: deck.id)
        shareImport.acknowledgeDrafts()
        showPreview = true
    }

    @MainActor
    private func importCapturedImage(_ image: UIImage, successBanner: String) async {
        isPreparingCapture = true
        var openedLiveText = false
        if LiveTextImageAnalyzer.isSupported {
            do {
                let analysis = try await LiveTextImageAnalyzer.analyze(image)
                let transcript = ImageOCRService.sanitizeOCRText(analysis.transcript)
                if analysis.hasResults(for: .text), !transcript.isEmpty {
                    liveTextDraft = LiveTextScanDraft(
                        image: image,
                        analysis: analysis,
                        successBanner: successBanner
                    )
                    openedLiveText = true
                }
            } catch {
                // Unsupported, empty, or analyzer error → existing Vision OCR.
            }
        }
        isPreparingCapture = false
        guard !openedLiveText else { return }

        isRunningOCR = true
        defer { isRunningOCR = false }
        await recognizeImage(image, successBanner: successBanner)
    }

    @MainActor
    private func applyLiveTextResult(_ result: LiveTextScanResult, image: UIImage, banner: String) {
        sentence = result.sentence
        sourceHint = OCRContextExtractor.sourceHint(from: result.sentence)
        sourceImagePath = CardSourceImageStore.saveJPEG(image)
        if let hint = sourceHint?.trimmingCharacters(in: .whitespacesAndNewlines), !hint.isEmpty {
            appreciationSource = hint
        }

        words = []
        var added = 0
        for word in result.words {
            if case .added = appendCreateWord(word) {
                added += 1
            }
        }

        if added > 0 {
            showToast(L10n.liveTextImported(added))
        } else {
            showToast(banner)
        }
        sourceMode = .pick
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
            sourceMode = .pick
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

            if result.importKind == .vocabPage {
                showToast(L10n.ocrVocabPage(result.preferredImportWords.count))
            } else if result.hasHighlightContext {
                showToast(L10n.ocrHighlightContext(
                    addedHighlights,
                    result.importUnits.count
                ))
            } else if addedHighlights > 0 {
                showToast(L10n.ocrHighlightDetected(addedHighlights))
            } else {
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
        let trimmed = VocabularyWords.normalized(word)
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
        if !hasSentence, let imagePath = payload.sourceImagePath,
           let image = CardSourceImageStore.loadUIImage(relativePath: imagePath) {
            shareImport.acknowledgeImport()
            Task { await importCapturedImage(image, successBanner: L10n.importFromPhotoSuccess) }
            return
        }

        sentence = payload.sentence
        sourceMode = .pick
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
        shareImport.acknowledgeImport()
    }

    @MainActor
    private func applyShareInboxIfNeeded() async {
        guard let inbox = shareImport.pendingInbox else { return }
        shareImport.acknowledgeInbox()
        switch inbox.kind {
        case .text:
            let text = inbox.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { return }
            sentence = text
            words = []
            sourceMode = .pick
            showToast(L10n.importShareSentence)
        case .image:
            guard let relativePath = inbox.relativePath,
                  let url = ShareImportStore.inboxFileURL(relativePath: relativePath) else {
                errorMessage = L10n.extensionNoContent
                return
            }
            AppLog.info("inbox OCR file=\(relativePath)", category: "Share")
            guard let image = CardSourceImageStore.imageForOCR(at: url) else {
                ShareImportStore.removeInboxFile(relativePath)
                errorMessage = L10n.ocrEmpty
                return
            }
            AppLog.info(
                "inbox OCR image \(Int(image.size.width))x\(Int(image.size.height))",
                category: "Share"
            )
            defer {
                ShareImportStore.removeInboxFile(relativePath)
            }
            await importCapturedImage(image, successBanner: L10n.importShareSentence)
        }
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
        Task {
            await aiQuota.refresh(force: true)
            enqueueGenerationNow()
        }
    }

    private func enqueueGenerationNow() {
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
            resetCreateWorkspace()
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
            var draft = try await LiteraryAppreciationGenerator.generate(from: reflection, allowFallback: false)
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
            generationQueue.enqueueTriage(drafts: [draft], deckID: deck.id)
            resetCreateWorkspace()
            showPreview = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct CreateCardsAlertsModifier: ViewModifier {
    @Binding var errorMessage: String?

    func body(content: Content) -> some View {
        content.onChange(of: errorMessage) { _, message in
            guard let message, !message.isEmpty else { return }
            ToastCenter.shared.show(message)
            errorMessage = nil
        }
    }
}

private struct CreateCardsLifecycleModifier: ViewModifier {
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
            .onChange(of: shareImport.pendingDrafts) { _, _ in
                onAppearImport()
            }
    }
}

#Preview {
    CreateCardsView()
        .environmentObject(ShareImportCoordinator())
        .environment(CloudAIQuotaStore.shared)
}

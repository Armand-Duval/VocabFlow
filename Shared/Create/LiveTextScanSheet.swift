import SwiftUI
#if canImport(UIKit)
import UIKit
import VisionKit

struct LiveTextScanDraft: Identifiable {
    let id = UUID()
    let image: UIImage
    let analysis: ImageAnalysis
    let successBanner: String
    /// Vision highlighter mask, started in parallel with Live Text analysis.
    let highlightDetection: Task<OCRResult, Error>
}

struct LiveTextScanResult {
    var sentence: String
    var words: [String]
}

enum LiveTextImageAnalyzer {
    private static let analyzer = ImageAnalyzer()

    /// Device / region / OS must all support Live Text. The app's floor is iOS 17,
    /// but `ImageAnalyzer.isSupported` can still be false on some hardware.
    static var isSupported: Bool {
        guard #available(iOS 16.0, *) else { return false }
        return ImageAnalyzer.isSupported
    }

    static func analyze(_ image: UIImage) async throws -> ImageAnalysis {
        var configuration = ImageAnalyzer.Configuration(.text)
        let supported = Set(ImageAnalyzer.supportedTextRecognitionLanguages)
        configuration.locales = ["en-US", "zh-Hans", "zh-Hant", "ja-JP"].filter(supported.contains)
        return try await analyzer.analyze(image, configuration: configuration)
    }
}

struct LiveTextScanSheet: View {
    let image: UIImage
    let analysis: ImageAnalysis
    let highlightDetection: Task<OCRResult, Error>
    var onComplete: (LiveTextScanResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedText = ""
    @State private var sentence: String
    @State private var words: [String] = []
    @State private var feedback: String?
    @State private var highlightsVisible = true
    @State private var isDetectingHighlights = true
    @State private var didApplyHighlights = false
    private let pageText: String

    init(
        image: UIImage,
        analysis: ImageAnalysis,
        highlightDetection: Task<OCRResult, Error>,
        onComplete: @escaping (LiveTextScanResult) -> Void
    ) {
        self.image = image
        self.analysis = analysis
        self.highlightDetection = highlightDetection
        self.onComplete = onComplete
        let transcript = ImageOCRService.sanitizeOCRText(analysis.transcript)
        pageText = transcript
        _sentence = State(initialValue: transcript)
    }

    private var trimmedSelection: String {
        selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ZStack(alignment: .bottomTrailing) {
                    LiveTextImageCanvas(
                        image: image,
                        analysis: analysis,
                        selectedText: $selectedText,
                        highlightsVisible: highlightsVisible
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Button {
                        highlightsVisible.toggle()
                    } label: {
                        Image(systemName: "text.viewfinder")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(highlightsVisible ? Color.white : AppColor.textPrimary)
                            .frame(width: 36, height: 36)
                            .background(
                                highlightsVisible ? AppColor.accentStrong : AppColor.surface,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(AppColor.border, lineWidth: 1)
                            }
                            .appSoftShadow()
                    }
                    .buttonStyle(SoftPressButtonStyle())
                    .padding(12)
                    .accessibilityLabel(L10n.liveTextToggleHighlights)
                    .accessibilityAddTraits(highlightsVisible ? .isSelected : [])
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                controls
            }
            .background(AppColor.pageBackground.ignoresSafeArea())
            .navigationTitle(L10n.liveTextTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.done, action: finish)
                        .fontWeight(.semibold)
                }
            }
            .task {
                await applyHighlighterWordsIfNeeded()
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(L10n.liveTextHint)
                .font(AppFont.helper())
                .foregroundStyle(AppColor.textMuted)

            if !trimmedSelection.isEmpty {
                Text(trimmedSelection)
                    .font(AppFont.body())
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if isDetectingHighlights, words.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L10n.liveTextDetectingHighlights)
                        .font(AppFont.helper())
                        .foregroundStyle(AppColor.textMuted)
                }
            }

            if !words.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                            LiveTextWordChip(word: word) {
                                words.remove(at: index)
                            }
                        }
                    }
                }
            }

            if let feedback {
                Text(feedback)
                    .font(AppFont.helper())
                    .foregroundStyle(AppColor.textSecondary)
            }

            HStack(spacing: AppSpacing.sm) {
                Button(L10n.liveTextAddWord, action: addSelectionAsWord)
                    .buttonStyle(PrimaryButtonStyle(soft: true))
                    .disabled(trimmedSelection.isEmpty)

                Button(L10n.liveTextUseAsSource, action: useSelectionAsSource)
                    .buttonStyle(PrimaryButtonStyle(soft: true))
                    .disabled(trimmedSelection.isEmpty)
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.top, AppSpacing.sm)
        .padding(.bottom, AppSpacing.md)
        .background {
            AppColor.pageBackground
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(AppColor.borderSubtle)
                        .frame(height: 1)
                }
        }
    }

    private func addSelectionAsWord() {
        let word = trimmedSelection
        guard !word.isEmpty else { return }
        switch VocabularyWords.append(word, to: &words) {
        case .added:
            feedback = L10n.wordAdded(word)
        case .duplicate:
            feedback = L10n.wordDuplicate(word)
        case .existsInDeck, .empty:
            feedback = L10n.wordDuplicate(word)
        }
    }

    private func useSelectionAsSource() {
        let text = trimmedSelection
        guard !text.isEmpty else { return }
        sentence = ImageOCRService.sanitizeOCRText(text)
        feedback = L10n.liveTextSourceUpdated
    }

    private func finish() {
        Task { @MainActor in
            await applyHighlighterWordsIfNeeded()
            let source = resolvedSourceText()
            guard !source.isEmpty else {
                feedback = L10n.ocrEmpty
                return
            }
            onComplete(LiveTextScanResult(sentence: source, words: words))
            dismiss()
        }
    }

    /// Seed highlighter vocabulary without blocking Live Text tap-to-select.
    @MainActor
    private func applyHighlighterWordsIfNeeded() async {
        guard !didApplyHighlights else { return }
        let result: OCRResult
        do {
            result = try await highlightDetection.value
        } catch {
            didApplyHighlights = true
            isDetectingHighlights = false
            return
        }
        didApplyHighlights = true
        isDetectingHighlights = false
        guard result.importKind == .highlight else { return }

        var added = 0
        let refined = HighlightPhraseMerger.refine(result.preferredImportWords, against: pageText)
        for word in refined {
            if case .added = VocabularyWords.append(word, to: &words) {
                added += 1
            }
        }
        if added > 0 {
            feedback = L10n.liveTextHighlightsDetected(added)
        }
    }

    /// Keep every selected word with its own sentence, not just the first hit.
    private func resolvedSourceText() -> String {
        let page = pageText.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty, !page.isEmpty else {
            return fallback.isEmpty ? page : fallback
        }

        let units = OCRContextExtractor.importUnits(fullText: page, highlightedWords: words)
        let joined = units
            .map(\.sentence)
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !joined.isEmpty { return joined }
        return fallback.isEmpty ? page : fallback
    }
}

private struct LiveTextImageCanvas: UIViewRepresentable {
    let image: UIImage
    let analysis: ImageAnalysis
    @Binding var selectedText: String
    var highlightsVisible: Bool

    func makeUIView(context: Context) -> LiveTextZoomView {
        let view = LiveTextZoomView()
        view.onSelectionChange = { selectedText = $0 }
        view.configure(image: image, analysis: analysis, highlightsVisible: highlightsVisible)
        return view
    }

    func updateUIView(_ uiView: LiveTextZoomView, context: Context) {
        uiView.onSelectionChange = { selectedText = $0 }
        uiView.setHighlightsVisible(highlightsVisible)
    }
}

final class LiveTextZoomView: UIView, UIScrollViewDelegate, ImageAnalysisInteractionDelegate {
    var onSelectionChange: ((String) -> Void)?

    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let interaction = ImageAnalysisInteraction()
    private var hasFittedZoom = false
    private var highlightsVisible = true
    private var hasRevealedHighlights = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5
        scrollView.bouncesZoom = true
        scrollView.backgroundColor = .clear
        imageView.contentMode = .scaleToFill
        imageView.isUserInteractionEnabled = true
        imageView.addInteraction(interaction)
        interaction.delegate = self
        interaction.allowLongPressForDataDetectorsInTextMode = false
        interaction.isSupplementaryInterfaceHidden = true
        addSubview(scrollView)
        scrollView.addSubview(imageView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(image: UIImage, analysis: ImageAnalysis, highlightsVisible: Bool) {
        self.highlightsVisible = highlightsVisible
        imageView.image = image
        imageView.frame = CGRect(origin: .zero, size: image.size)
        scrollView.contentSize = image.size
        interaction.analysis = analysis
        interaction.preferredInteractionTypes = .automaticTextOnly
        hasFittedZoom = false
        hasRevealedHighlights = false
        setNeedsLayout()
    }

    func setHighlightsVisible(_ visible: Bool) {
        highlightsVisible = visible
        guard hasRevealedHighlights else { return }
        applyHighlights()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
        guard !hasFittedZoom, bounds.width > 1, let image = imageView.image else { return }
        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        scrollView.minimumZoomScale = scale
        scrollView.zoomScale = scale
        hasFittedZoom = true
        centerImage()
        playScanReveal()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
    }

    func textSelectionDidChange(_ interaction: ImageAnalysisInteraction) {
        onSelectionChange?(interaction.selectedText)
    }

    private func playScanReveal() {
        guard !hasRevealedHighlights else { return }
        interaction.selectableItemsHighlighted = false

        let line = UIView()
        line.isUserInteractionEnabled = false
        line.backgroundColor = UIColor(AppColor.accent).withAlphaComponent(0.38)
        line.frame = CGRect(x: 0, y: -2, width: bounds.width, height: 2)
        addSubview(line)

        UIView.animate(withDuration: 0.55, delay: 0.06, options: .curveEaseInOut, animations: {
            line.frame.origin.y = self.bounds.height
        }, completion: { _ in
            line.removeFromSuperview()
            self.hasRevealedHighlights = true
            self.applyHighlights()
        })
    }

    private func applyHighlights() {
        interaction.selectableItemsHighlighted = highlightsVisible
        // Assigning analysis can clear this flag; restore on the next run loop.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.interaction.selectableItemsHighlighted = self.highlightsVisible
        }
    }

    private func centerImage() {
        let bounds = scrollView.bounds.size
        let insetX = max((bounds.width - scrollView.contentSize.width) / 2, 0)
        let insetY = max((bounds.height - scrollView.contentSize.height) / 2, 0)
        scrollView.contentInset = UIEdgeInsets(top: insetY, left: insetX, bottom: insetY, right: insetX)
    }
}

private struct LiveTextWordChip: View {
    let word: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(word)
                .font(AppFont.helper())
                .foregroundStyle(AppColor.accent)
                .lineLimit(1)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppColor.textMuted)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(L10n.cancel))
        }
        .padding(.leading, AppSpacing.sm)
        .padding(.trailing, 6)
        .padding(.vertical, 5)
        .background(AppColor.accentBackground(0.12), in: Capsule())
    }
}
#endif

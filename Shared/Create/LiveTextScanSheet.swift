import SwiftUI
#if canImport(UIKit)
import UIKit
import VisionKit

struct LiveTextScanDraft: Identifiable {
    let id = UUID()
    let image: UIImage
    let analysis: ImageAnalysis
    let successBanner: String
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
    var onComplete: (LiveTextScanResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedText = ""
    @State private var sentence: String
    @State private var words: [String] = []
    @State private var feedback: String?

    init(image: UIImage, analysis: ImageAnalysis, onComplete: @escaping (LiveTextScanResult) -> Void) {
        self.image = image
        self.analysis = analysis
        self.onComplete = onComplete
        let transcript = ImageOCRService.sanitizeOCRText(analysis.transcript)
        _sentence = State(initialValue: transcript)
    }

    private var trimmedSelection: String {
        selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                LiveTextImageCanvas(
                    image: image,
                    analysis: analysis,
                    selectedText: $selectedText
                )
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

            if !words.isEmpty {
                Text(words.joined(separator: " · "))
                    .font(AppFont.helper())
                    .foregroundStyle(AppColor.accent)
                    .lineLimit(2)
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
            if sentence.count > 220, let around = OCRContextExtractor.sentenceContaining(word, in: sentence) {
                sentence = around
            }
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
        let text = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            feedback = L10n.ocrEmpty
            return
        }
        onComplete(LiveTextScanResult(sentence: text, words: words))
        dismiss()
    }
}

private struct LiveTextImageCanvas: UIViewRepresentable {
    let image: UIImage
    let analysis: ImageAnalysis
    @Binding var selectedText: String

    func makeUIView(context: Context) -> LiveTextZoomView {
        let view = LiveTextZoomView()
        view.onSelectionChange = { selectedText = $0 }
        view.configure(image: image, analysis: analysis)
        return view
    }

    func updateUIView(_ uiView: LiveTextZoomView, context: Context) {
        uiView.onSelectionChange = { selectedText = $0 }
    }
}

final class LiveTextZoomView: UIView, UIScrollViewDelegate, ImageAnalysisInteractionDelegate {
    var onSelectionChange: ((String) -> Void)?

    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let interaction = ImageAnalysisInteraction()
    private var hasFittedZoom = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5
        scrollView.bouncesZoom = true
        scrollView.backgroundColor = .clear
        imageView.contentMode = .scaleToFill
        imageView.isUserInteractionEnabled = true
        imageView.addInteraction(interaction)
        interaction.delegate = self
        interaction.preferredInteractionTypes = .textSelection
        interaction.allowLongPressForDataDetectorsInTextMode = false
        interaction.isSupplementaryInterfaceHidden = true
        addSubview(scrollView)
        scrollView.addSubview(imageView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(image: UIImage, analysis: ImageAnalysis) {
        imageView.image = image
        imageView.frame = CGRect(origin: .zero, size: image.size)
        scrollView.contentSize = image.size
        interaction.analysis = analysis
        hasFittedZoom = false
        setNeedsLayout()
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
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
    }

    func textSelectionDidChange(_ interaction: ImageAnalysisInteraction) {
        onSelectionChange?(interaction.selectedText)
    }

    private func centerImage() {
        let bounds = scrollView.bounds.size
        let insetX = max((bounds.width - scrollView.contentSize.width) / 2, 0)
        let insetY = max((bounds.height - scrollView.contentSize.height) / 2, 0)
        scrollView.contentInset = UIEdgeInsets(top: insetY, left: insetX, bottom: insetY, right: insetX)
    }
}
#endif

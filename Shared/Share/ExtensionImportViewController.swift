import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Share / Action entry: extract content, then keep the create form on screen.
/// Never auto-dismiss on load failure — that felt like a flash crash.
class ExtensionImportViewController: UIViewController {
    private var didFinishRequest = false
    private var hostingController: UIHostingController<AnyView>?
    private var statusLabel: UILabel?
    private var closeButton: UIButton?

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = CGSize(width: 390, height: 640)
        view.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.11, green: 0.12, blue: 0.12, alpha: 1)
                : UIColor(red: 0.965, green: 0.961, blue: 0.949, alpha: 1)
        }
        showStatus(L10n.extensionHint)
        extractSharedContent()
    }

    private func extractSharedContent() {
        guard let inputItems = extensionContext?.inputItems as? [NSExtensionItem], !inputItems.isEmpty else {
            showRecoverableError(L10n.extensionNoContent)
            return
        }

        if let text = ShareTextExtractor.attributedText(from: inputItems) {
            presentEditor(sentence: text, highlightedWords: [], sourceHint: nil, sourceImagePath: nil, preferSharedSentence: false)
            return
        }

        Task { @MainActor in
            await Task.yield()

            let outcome = await Self.loadSharedContent(from: inputItems, timeoutSeconds: 20)
            switch outcome {
            case .text(let text):
                presentEditor(sentence: text, highlightedWords: [], sourceHint: nil, sourceImagePath: nil, preferSharedSentence: false)
            case .ocr(let ocr):
                presentOCREditor(ocr)
            case .ocrFailed:
                showRecoverableError(L10n.extensionOCRFailed)
            case .timeout:
                showRecoverableError(L10n.extensionTimeout)
            case .empty:
                showRecoverableError(L10n.extensionNoText)
            }
        }
    }

    private enum SharedLoadOutcome {
        case text(String)
        case ocr(OCRResult)
        case ocrFailed
        case timeout
        case empty
    }

    private static func loadSharedContent(
        from inputItems: [NSExtensionItem],
        timeoutSeconds: Double
    ) async -> SharedLoadOutcome {
        await withTaskGroup(of: SharedLoadOutcome.self) { group in
            group.addTask {
                if let text = await ShareTextExtractor.loadText(from: inputItems) {
                    return .text(text)
                }

                #if canImport(UIKit)
                let providers = inputItems.flatMap { $0.attachments ?? [] }
                let hasImage = providers.contains { provider in
                    provider.hasItemConformingToTypeIdentifier(UTType.image.identifier)
                        || provider.hasItemConformingToTypeIdentifier(UTType.jpeg.identifier)
                        || provider.hasItemConformingToTypeIdentifier(UTType.png.identifier)
                        || provider.hasItemConformingToTypeIdentifier("public.image")
                }
                if hasImage {
                    if let ocr = await ShareTextExtractor.loadOCRFromImages(from: inputItems) {
                        return .ocr(ocr)
                    }
                    return .ocrFailed
                }
                #endif

                return .empty
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                return .timeout
            }

            let first = await group.next() ?? .empty
            group.cancelAll()
            return first
        }
    }

    private func presentOCREditor(_ ocr: OCRResult) {
        let hint = OCRContextExtractor.sourceHint(from: ocr.fullText)
        if ocr.hasHighlightContext {
            presentEditor(
                sentence: ocr.preferredImportSentence,
                highlightedWords: ocr.preferredImportWords,
                sourceHint: hint,
                sourceImagePath: ocr.sourceImagePath,
                preferSharedSentence: true
            )
        } else {
            presentEditor(
                sentence: ocr.fullText,
                highlightedWords: ocr.highlightedWords,
                sourceHint: hint,
                sourceImagePath: ocr.sourceImagePath,
                preferSharedSentence: false
            )
        }
    }

    private func presentEditor(
        sentence raw: String,
        highlightedWords: [String],
        sourceHint: String?,
        sourceImagePath: String?,
        preferSharedSentence: Bool
    ) {
        let parsed = ImportTextAnalyzer.parse(raw)
        var words = preferSharedSentence ? [] : parsed.prefilledWords
        for word in highlightedWords {
            _ = VocabularyWords.append(word, to: &words)
        }
        let sentence: String
        if preferSharedSentence {
            sentence = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            let fromParser = parsed.sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            sentence = fromParser.isEmpty ? raw.trimmingCharacters(in: .whitespacesAndNewlines) : fromParser
        }

        guard !sentence.isEmpty else {
            showRecoverableError(L10n.extensionNoText)
            return
        }

        ShareImportStore.save(
            sentence: sentence,
            selectedWord: words.isEmpty ? nil : VocabularyWords.join(words),
            sourceHint: sourceHint,
            sourceImagePath: sourceImagePath
        )

        let form = ImportCardsFormView(
            sentence: sentence,
            selectedWord: words.isEmpty ? nil : VocabularyWords.join(words),
            sourceHint: sourceHint,
            sourceImagePath: sourceImagePath,
            onSubmit: { [weak self] in
                self?.completeExtension()
            },
            onCancel: { [weak self] in
                ShareImportStore.clear()
                self?.cancelExtension()
            }
        )

        statusLabel?.removeFromSuperview()
        statusLabel = nil
        closeButton?.removeFromSuperview()
        closeButton = nil

        hostingController?.willMove(toParent: nil)
        hostingController?.view.removeFromSuperview()
        hostingController?.removeFromParent()

        let host = UIHostingController(rootView: AnyView(form))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
        hostingController = host
    }

    private func showStatus(_ message: String) {
        let label = statusLabel ?? {
            let created = UILabel()
            created.textAlignment = .center
            created.numberOfLines = 0
            created.font = .preferredFont(forTextStyle: .body)
            created.textColor = .secondaryLabel
            created.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(created)
            NSLayoutConstraint.activate([
                created.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                created.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -24),
                created.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
                created.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28)
            ])
            statusLabel = created
            return created
        }()
        label.text = message
    }

    /// Stay on screen — auto cancelRequest looked like a crash to users.
    private func showRecoverableError(_ message: String) {
        showStatus(message)
        if closeButton == nil {
            let button = UIButton(type: .system)
            button.setTitle(L10n.close, for: .normal)
            button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
            view.addSubview(button)
            NSLayoutConstraint.activate([
                button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                button.topAnchor.constraint(equalTo: statusLabel?.bottomAnchor ?? view.centerYAnchor, constant: 20)
            ])
            closeButton = button
        }
    }

    @objc private func closeTapped() {
        cancelExtension()
    }

    private func completeExtension() {
        guard !didFinishRequest else { return }
        didFinishRequest = true
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func cancelExtension() {
        guard !didFinishRequest else { return }
        didFinishRequest = true
        extensionContext?.cancelRequest(withError: NSError(domain: "KnoWellShare", code: 0, userInfo: [
            NSLocalizedDescriptionKey: L10n.cancel
        ]))
    }
}

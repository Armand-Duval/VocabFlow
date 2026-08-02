import SwiftUI
import UIKit

class ExtensionImportViewController: UIViewController {
    private var hostingController: UIHostingController<AnyView>?
    private var didFinishRequest = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        extractSharedText()
    }

    private func extractSharedText() {
        guard let inputItems = extensionContext?.inputItems as? [NSExtensionItem], !inputItems.isEmpty else {
            finishWithError(L10n.extensionNoContent)
            return
        }

        if let text = ShareTextExtractor.attributedText(from: inputItems) {
            presentImportForm(for: text)
            return
        }

        Task { @MainActor in
            if let text = await ShareTextExtractor.loadText(from: inputItems) {
                presentImportForm(for: text)
            } else if let ocr = await ShareTextExtractor.loadOCRFromImages(from: inputItems) {
                presentImportForm(ocr: ocr)
            } else {
                finishWithError(L10n.extensionNoText)
            }
        }
    }

    private func presentImportForm(ocr: OCRResult) {
        let hint = OCRContextExtractor.sourceHint(from: ocr.fullText)
        if ocr.hasHighlightContext {
            presentImportForm(
                for: ocr.preferredImportSentence,
                highlightedWords: ocr.preferredImportWords,
                sourceHint: hint,
                sourceImagePath: ocr.sourceImagePath,
                replaceSentence: true
            )
        } else {
            presentImportForm(
                for: ocr.fullText,
                highlightedWords: ocr.highlightedWords,
                sourceHint: hint,
                sourceImagePath: ocr.sourceImagePath
            )
        }
    }

    private func presentImportForm(
        for text: String,
        highlightedWords: [String] = [],
        sourceHint: String? = nil,
        sourceImagePath: String? = nil,
        replaceSentence: Bool = false
    ) {
        let parsed = ImportTextAnalyzer.parse(text)
        var prefilled = replaceSentence ? [] : parsed.prefilledWords
        for word in highlightedWords {
            _ = VocabularyWords.append(word, to: &prefilled)
        }
        let sentence: String
        if replaceSentence {
            sentence = text
        } else {
            sentence = parsed.sentence.isEmpty ? text : parsed.sentence
        }
        let formView = ImportCardsFormView(
            sentence: sentence,
            selectedWord: prefilled.isEmpty ? nil : VocabularyWords.join(prefilled),
            sourceHint: sourceHint,
            sourceImagePath: sourceImagePath,
            onSubmit: { [weak self] in
                self?.finishAfterQueued()
            },
            onCancel: { [weak self] in
                self?.completeExtension()
            }
        )

        let hosting = UIHostingController(rootView: AnyView(formView))
        hosting.view.translatesAutoresizingMaskIntoConstraints = false

        addChild(hosting)
        view.addSubview(hosting.view)

        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        hosting.didMove(toParent: self)
        hostingController = hosting
    }

    private func finishAfterQueued() {
        // Wake the host app so Share / Action pending jobs enter CardGenerationQueue immediately.
        if let url = URL(string: ShareImportStore.createURLString) {
            extensionContext?.open(url) { [weak self] _ in
                self?.completeExtension()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.completeExtension()
            }
            return
        }
        completeExtension()
    }

    private func completeExtension() {
        guard !didFinishRequest else { return }
        didFinishRequest = true
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func finishWithError(_ message: String) {
        let label = UILabel()
        label.text = message
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
        ])

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            let error = NSError(domain: "KnoWellShare", code: 1, userInfo: [
                NSLocalizedDescriptionKey: message
            ])
            self?.extensionContext?.cancelRequest(withError: error)
        }
    }
}

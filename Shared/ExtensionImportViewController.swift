import SwiftUI
import UIKit

class ExtensionImportViewController: UIViewController {
    private var hostingController: UIHostingController<AnyView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        extractSharedText()
    }

    private func extractSharedText() {
        guard let inputItems = extensionContext?.inputItems as? [NSExtensionItem], !inputItems.isEmpty else {
            finishWithError("没有收到分享内容")
            return
        }

        if let text = ShareTextExtractor.attributedText(from: inputItems) {
            presentImportForm(sentence: text)
            return
        }

        Task { @MainActor in
            if let text = await ShareTextExtractor.loadText(from: inputItems) {
                presentImportForm(sentence: text)
            } else {
                finishWithError("未读到文字内容，请用「拷贝」后打开 VocabFlow")
            }
        }
    }

    private func presentImportForm(sentence: String) {
        let formView = ImportCardsFormView(
            sentence: sentence,
            onSubmit: { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            },
            onCancel: { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
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
            let error = NSError(domain: "VocabFlowShare", code: 1, userInfo: [
                NSLocalizedDescriptionKey: message
            ])
            self?.extensionContext?.cancelRequest(withError: error)
        }
    }
}

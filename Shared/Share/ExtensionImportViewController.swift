import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Share / Action: copy images to the app, keep text editing here.
class ExtensionImportViewController: UIViewController {
    private var didFinishRequest = false
    private var didStartHandoff = false
    private var hostingController: UIHostingController<AnyView>?
    private let session = ExtensionImportSession()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.11, green: 0.12, blue: 0.12, alpha: 1)
                : UIColor(red: 0.965, green: 0.961, blue: 0.949, alpha: 1)
        }
        AppLog.bootstrap()
        AppLog.info(
            "viewDidLoad frame=\(Int(view.bounds.width))x\(Int(view.bounds.height)) items=\(extensionContext?.inputItems.count ?? -1)",
            category: "Share"
        )
        installRoot()
        startHandoffIfNeeded()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        AppLog.info(
            "viewWillAppear frame=\(Int(view.bounds.width))x\(Int(view.bounds.height))",
            category: "Share"
        )
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        AppLog.info(
            "viewDidAppear frame=\(Int(view.frame.width))x\(Int(view.frame.height))",
            category: "Share"
        )
        startHandoffIfNeeded()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        AppLog.info("viewDidDisappear finished=\(didFinishRequest)", category: "Share")
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        AppLog.warn("memory warning", category: "Share")
    }

    private func installRoot() {
        let root = ExtensionImportRoot(
            session: session,
            onSubmit: { [weak self] in
                self?.completeExtension()
            },
            onOpenApp: { [weak self] responder in
                self?.openHostAppFromUserTap(from: responder)
            },
            onFinish: { [weak self] in
                self?.completeExtension()
            },
            onCancel: { [weak self] in
                self?.cancelExtension()
            }
        )
        let host = UIHostingController(rootView: AnyView(root))
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

    private func startHandoffIfNeeded() {
        guard !didStartHandoff else { return }
        didStartHandoff = true
        handoffSharedContent()
    }

    private func handoffSharedContent() {
        guard let inputItems = extensionContext?.inputItems as? [NSExtensionItem], !inputItems.isEmpty else {
            AppLog.warn("handoff: no input items", category: "Share")
            session.fail(L10n.extensionNoContent)
            return
        }

        let attachmentCount = inputItems.reduce(0) { $0 + ($1.attachments?.count ?? 0) }
        AppLog.info("handoff start items=\(inputItems.count) attachments=\(attachmentCount)", category: "Share")

        Task {
            if ShareTextExtractor.hasImageAttachment(in: inputItems) {
                if let relativePath = await ShareTextExtractor.ingestFirstImage(from: inputItems) {
                    AppLog.info("handoff inbox file=\(relativePath)", category: "Share")
                    ShareImportStore.saveInbox(
                        ShareInboxPayload(kind: .image, text: nil, relativePath: relativePath)
                    )
                    await MainActor.run {
                        finishHandoff(autoOpen: true)
                    }
                } else {
                    AppLog.warn("handoff image ingest failed", category: "Share")
                    await MainActor.run {
                        session.fail(L10n.extensionNoContent)
                    }
                }
                return
            }

            let text: String?
            if let attributed = ShareTextExtractor.attributedText(from: inputItems) {
                text = attributed
            } else {
                text = await ShareTextExtractor.loadText(from: inputItems)
            }
            await MainActor.run {
                if let text {
                    AppLog.info("extension text chars=\(text.count)", category: "Share")
                    presentEditor(
                        sentence: text,
                        highlightedWords: [],
                        sourceHint: nil,
                        sourceImagePath: nil,
                        preferSharedSentence: false
                    )
                } else {
                    AppLog.warn("handoff empty", category: "Share")
                    session.fail(L10n.extensionNoText)
                }
            }
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
            AppLog.warn("presentEditor empty sentence", category: "Share")
            session.fail(L10n.extensionNoText)
            return
        }

        AppLog.info(
            "presentEditor chars=\(sentence.count) words=\(words.count) hint=\(sourceHint ?? "-") image=\(sourceImagePath != nil)",
            category: "Share"
        )
        session.showForm(
            sentence: sentence,
            selectedWord: words.isEmpty ? nil : VocabularyWords.join(words),
            sourceHint: sourceHint,
            sourceImagePath: sourceImagePath
        )
    }

    /// Images are handed to the host app. Open immediately; keep a button if iOS blocks the jump.
    private func finishHandoff(autoOpen: Bool) {
        AppLog.info("handoff ready autoOpen=\(autoOpen)", category: "Share")
        if autoOpen, openContainingApp(from: self) {
            AppLog.info("auto-open dispatched — completing extension", category: "Share")
            completeExtension()
            return
        }
        session.markHandedOff()
    }

    private func openHostAppFromUserTap(from responder: UIResponder?) {
        AppLog.info("open host from button", category: "Share")
        let opened = openContainingApp(from: responder) || openContainingApp(from: self)
        AppLog.info("open host dispatched=\(opened)", category: "Share")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.completeExtension()
        }
    }

    @discardableResult
    private func openContainingApp(from responder: UIResponder?) -> Bool {
        guard let url = URL(string: ShareImportStore.createURLString) else { return false }
        let starts: [UIResponder] = [responder, self, hostingController, view.window, view].compactMap { $0 }
        var seen = Set<ObjectIdentifier>()
        for start in starts {
            let id = ObjectIdentifier(start)
            guard seen.insert(id).inserted else { continue }
            if KWExtensionOpenURL(url, start) {
                AppLog.info("KWExtensionOpenURL from \(type(of: start))", category: "Share")
                return true
            }
        }
        if let application = uiApplicationShared() {
            AppLog.info("UIApplication via sharedApplication selector", category: "Share")
            application.open(url, options: [:]) { success in
                AppLog.info("sharedApplication.open success=\(success)", category: "Share")
            }
            return true
        }
        extensionContext?.open(url) { success in
            AppLog.info("extensionContext.open success=\(success)", category: "Share")
        }
        return false
    }

    private func uiApplicationShared() -> UIApplication? {
        let selector = NSSelectorFromString("sharedApplication")
        let appClass = unsafeBitCast(UIApplication.self, to: AnyObject.self)
        guard appClass.responds(to: selector) else { return nil }
        return appClass.perform(selector)?.takeUnretainedValue() as? UIApplication
    }

    private func completeExtension() {
        guard !didFinishRequest else { return }
        didFinishRequest = true
        AppLog.info("completeRequest", category: "Share")
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func cancelExtension() {
        guard !didFinishRequest else { return }
        didFinishRequest = true
        AppLog.info("cancelRequest", category: "Share")
        extensionContext?.cancelRequest(withError: NSError(domain: "KnoWellShare", code: 0, userInfo: [
            NSLocalizedDescriptionKey: L10n.cancel
        ]))
    }
}

@MainActor
final class ExtensionImportSession: ObservableObject {
    enum Phase {
        case loading
        case ready(sentence: String, selectedWord: String?, sourceHint: String?, sourceImagePath: String?)
        case handedOff
        case failed(String)
    }

    @Published var phase: Phase = .loading

    func showForm(
        sentence: String,
        selectedWord: String?,
        sourceHint: String?,
        sourceImagePath: String?
    ) {
        phase = .ready(
            sentence: sentence,
            selectedWord: selectedWord,
            sourceHint: sourceHint,
            sourceImagePath: sourceImagePath
        )
    }

    func markHandedOff() {
        phase = .handedOff
    }

    func fail(_ message: String) {
        phase = .failed(message)
    }
}

private struct ExtensionImportRoot: View {
    @ObservedObject var session: ExtensionImportSession
    let onSubmit: () -> Void
    let onOpenApp: (UIResponder?) -> Void
    let onFinish: () -> Void
    let onCancel: () -> Void

    var body: some View {
        switch session.phase {
        case .loading:
            NavigationStack {
                VStack(spacing: AppSpacing.md) {
                    ProgressView()
                    Text(L10n.extensionHint)
                        .font(AppFont.secondary())
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.lg)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .appPageBackground()
                .navigationTitle(L10n.createTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.cancel, action: onCancel)
                    }
                }
            }
        case let .ready(sentence, selectedWord, sourceHint, sourceImagePath):
            ImportCardsFormView(
                sentence: sentence,
                selectedWord: selectedWord,
                sourceHint: sourceHint,
                sourceImagePath: sourceImagePath,
                onSubmit: onSubmit,
                onCancel: onCancel
            )
        case .handedOff:
            NavigationStack {
                VStack(spacing: AppSpacing.md) {
                    Image(systemName: "photo")
                        .font(.system(size: 36))
                        .foregroundStyle(AppColor.accent)
                    Text(L10n.extensionHandedOff)
                        .font(AppFont.secondary().weight(.semibold))
                        .foregroundStyle(AppColor.textPrimary)
                    Text(L10n.extensionHandedOffReason)
                        .font(AppFont.secondary())
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.lg)
                    HostOpenButton(title: L10n.extensionOpenApp) { button in
                        onOpenApp(button)
                    }
                    .frame(height: 48)
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.top, AppSpacing.sm)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .appPageBackground()
                .navigationTitle(L10n.createTitle)
                .navigationBarTitleDisplayMode(.inline)
            }
        case let .failed(message):
            NavigationStack {
                VStack(spacing: AppSpacing.md) {
                    Text(message)
                        .font(AppFont.secondary())
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.lg)
                    Button(L10n.close, action: onCancel)
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.horizontal, AppSpacing.xl)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .appPageBackground()
                .navigationTitle(L10n.createTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.cancel, action: onCancel)
                    }
                }
            }
        }
    }
}

/// UIKit control so the tap stays a real user gesture on the responder chain.
private struct HostOpenButton: UIViewRepresentable {
    let title: String
    let onTap: (UIButton) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }

    func makeUIView(context: Context) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.baseBackgroundColor = UIColor(AppColor.accent)
        config.baseForegroundColor = .white
        config.cornerStyle = .large
        config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 16, weight: .semibold)
            return outgoing
        }
        let button = UIButton(configuration: config)
        button.addTarget(context.coordinator, action: #selector(Coordinator.tapped(_:)), for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: UIButton, context: Context) {
        context.coordinator.onTap = onTap
        uiView.configuration?.title = title
    }

    final class Coordinator: NSObject {
        var onTap: (UIButton) -> Void

        init(onTap: @escaping (UIButton) -> Void) {
            self.onTap = onTap
        }

        @objc func tapped(_ sender: UIButton) {
            onTap(sender)
        }
    }
}

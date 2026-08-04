import SwiftUI
import UIKit

/// Read-only selectable study text with highlight + selection menu (lookup / highlight / create).
struct SelectableStudyText: UIViewRepresentable {
    let text: String
    let highlightTerms: [String]
    var matchStyle: HighlightMatchStyle = .wordBounded
    var font: UIFont = UIFont.preferredFont(forTextStyle: .body)
    var onLookup: ((String) -> Void)?
    var onSetHighlight: ((String) -> Void)?
    var onCreateCard: ((String) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = IntrinsicTextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.defaultHigh, for: .vertical)
        context.coordinator.textView = textView
        context.coordinator.applyAttributedText(to: textView)

        if #available(iOS 16.0, *) {
            let interaction = UIEditMenuInteraction(delegate: context.coordinator)
            textView.addInteraction(interaction)
            context.coordinator.editMenuInteraction = interaction
        }

        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        let current = textView.attributedText?.string ?? ""
        if current != text
            || context.coordinator.lastTerms != highlightTerms
            || context.coordinator.lastStyle != matchStyle {
            context.coordinator.applyAttributedText(to: textView)
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIEditMenuInteractionDelegate {
        var parent: SelectableStudyText
        weak var textView: UITextView?
        weak var editMenuInteraction: UIEditMenuInteraction?
        var lastTerms: [String] = []
        var lastStyle: HighlightMatchStyle = .wordBounded

        init(parent: SelectableStudyText) {
            self.parent = parent
        }

        func applyAttributedText(to textView: UITextView) {
            lastTerms = parent.highlightTerms
            lastStyle = parent.matchStyle
            let background = UIColor(AppColor.accentBackground(0.24))
            let textColor = UIColor(AppColor.textPrimary)
            textView.attributedText = HighlightMatcher.attributedString(
                text: parent.text,
                terms: parent.highlightTerms,
                style: parent.matchStyle,
                font: parent.font,
                textColor: textColor,
                highlightBackground: background,
                highlightForeground: nil,
                semibold: true
            )
            textView.invalidateIntrinsicContentSize()
        }

        @available(iOS 16.0, *)
        func editMenuInteraction(
            _ interaction: UIEditMenuInteraction,
            menuFor configuration: UIEditMenuConfiguration,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            guard let selection = trimmedSelection() else {
                return UIMenu(children: suggestedActions)
            }

            var actions: [UIMenuElement] = []

            if parent.onLookup != nil {
                actions.append(UIAction(
                    title: L10n.studySelectionLookup,
                    image: UIImage(systemName: "character.book.closed")
                ) { [weak self] _ in
                    guard let self else { return }
                    StudyDictionaryLookup.present(term: selection, from: self.textView)
                    self.parent.onLookup?(selection)
                })
            }

            if parent.onSetHighlight != nil {
                actions.append(UIAction(
                    title: L10n.studySelectionSetHighlight,
                    image: UIImage(systemName: "highlighter")
                ) { [weak self] _ in
                    self?.parent.onSetHighlight?(selection)
                    self?.clearSelection()
                })
            }

            if parent.onCreateCard != nil {
                actions.append(UIAction(
                    title: L10n.studySelectionCreateCard,
                    image: UIImage(systemName: "plus.circle")
                ) { [weak self] _ in
                    self?.parent.onCreateCard?(selection)
                    self?.clearSelection()
                })
            }

            return UIMenu(children: actions + suggestedActions)
        }

        private func trimmedSelection() -> String? {
            guard let textView,
                  textView.selectedRange.length > 0,
                  let range = Range(textView.selectedRange, in: textView.text ?? "") else {
                return nil
            }
            let value = String((textView.text ?? "")[range])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }

        private func clearSelection() {
            guard let textView else { return }
            let location = textView.selectedRange.location
            textView.selectedRange = NSRange(location: location, length: 0)
        }
    }
}

private final class IntrinsicTextView: UITextView {
    override var intrinsicContentSize: CGSize {
        let width = bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width
        let size = sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: UIView.noIntrinsicMetric, height: ceil(size.height))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        invalidateIntrinsicContentSize()
    }
}

/// Presents system dictionary lookup when available.
enum StudyDictionaryLookup {
    @MainActor
    static func present(term: String, from sourceView: UIView? = nil) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: trimmed) {
            let controller = UIReferenceLibraryViewController(term: trimmed)
            guard let host = presenter(from: sourceView) else {
                ToastCenter.shared.show(L10n.studySelectionLookupUnavailable)
                return
            }
            host.present(controller, animated: true)
        } else {
            ToastCenter.shared.show(L10n.studySelectionLookupUnavailable)
        }
    }

    @MainActor
    private static func presenter(from sourceView: UIView?) -> UIViewController? {
        var responder: UIResponder? = sourceView
        while let current = responder {
            if let viewController = current as? UIViewController {
                return topMost(from: viewController)
            }
            responder = current.next
        }
        if let root = sourceView?.window?.rootViewController {
            return topMost(from: root)
        }
        return nil
    }

    @MainActor
    private static func topMost(from base: UIViewController) -> UIViewController {
        if let nav = base as? UINavigationController, let visible = nav.visibleViewController {
            return topMost(from: visible)
        }
        if let tab = base as? UITabBarController, let selected = tab.selectedViewController {
            return topMost(from: selected)
        }
        if let presented = base.presentedViewController {
            return topMost(from: presented)
        }
        return base
    }
}

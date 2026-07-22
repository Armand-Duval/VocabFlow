import SwiftUI
import UIKit

/// 基于 UITextView 的可编辑文本区，支持系统原生拖选。
struct SelectableTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedText: String
    @Binding var selectionClearNonce: Int
    var minHeight: CGFloat = 120
    var onAddToVocabulary: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = AutoSizingTextView(minHeight: minHeight)
        textView.delegate = context.coordinator
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        textView.textContainer.lineFragmentPadding = 0
        textView.isEditable = true
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.text = text
        context.coordinator.textView = textView

        if #available(iOS 16.0, *) {
            let interaction = UIEditMenuInteraction(delegate: context.coordinator)
            textView.addInteraction(interaction)
            context.coordinator.editMenuInteraction = interaction
        }

        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self

        if textView.text != text {
            textView.text = text
            textView.invalidateIntrinsicContentSize()
        }

        if context.coordinator.lastClearNonce != selectionClearNonce {
            context.coordinator.lastClearNonce = selectionClearNonce
            let location = textView.selectedRange.location
            textView.selectedRange = NSRange(location: location, length: 0)
            if selectedText.isEmpty == false {
                DispatchQueue.main.async {
                    selectedText = ""
                }
            }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIEditMenuInteractionDelegate {
        var parent: SelectableTextEditor
        weak var textView: UITextView?
        var lastClearNonce = 0
        weak var editMenuInteraction: UIEditMenuInteraction?

        init(parent: SelectableTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            textView.invalidateIntrinsicContentSize()
            publishSelection(from: textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            publishSelection(from: textView)
        }

        @available(iOS 16.0, *)
        func editMenuInteraction(
            _ interaction: UIEditMenuInteraction,
            menuFor configuration: UIEditMenuConfiguration,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            guard let textView,
                  textView.selectedRange.length > 0,
                  trimmedSelection(from: textView) != nil else {
                return UIMenu(children: suggestedActions)
            }

            let addAction = UIAction(
                title: L10n.addToVocabulary,
                image: UIImage(systemName: "plus.circle")
            ) { [weak self] _ in
                self?.parent.onAddToVocabulary?()
            }

            return UIMenu(children: suggestedActions + [addAction])
        }

        private func publishSelection(from textView: UITextView) {
            let selection = trimmedSelection(from: textView) ?? ""
            if parent.selectedText != selection {
                parent.selectedText = selection
            }
        }

        private func trimmedSelection(from textView: UITextView) -> String? {
            guard textView.selectedRange.length > 0,
                  let selectedRange = Range(textView.selectedRange, in: textView.text) else {
                return nil
            }
            let value = String(textView.text[selectedRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
    }
}

private final class AutoSizingTextView: UITextView {
    private let minHeight: CGFloat

    init(minHeight: CGFloat) {
        self.minHeight = minHeight
        super.init(frame: .zero, textContainer: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        let width = bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width - 64
        let fittingSize = sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: UIView.noIntrinsicMetric, height: max(minHeight, fittingSize.height))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        invalidateIntrinsicContentSize()
    }
}

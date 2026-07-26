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
        textView.inputAccessoryView = context.coordinator.makeInputAccessoryView()

        let dismissPan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleKeyboardDismissPan(_:))
        )
        dismissPan.delegate = context.coordinator
        dismissPan.cancelsTouchesInView = false
        textView.addGestureRecognizer(dismissPan)
        context.coordinator.dismissPanRecognizer = dismissPan

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
            context.coordinator.applySelectionStyle(to: textView)
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

    final class Coordinator: NSObject, UITextViewDelegate, UIEditMenuInteractionDelegate, UIGestureRecognizerDelegate {
        var parent: SelectableTextEditor
        weak var textView: UITextView?
        weak var dismissPanRecognizer: UIPanGestureRecognizer?
        var lastClearNonce = 0
        weak var editMenuInteraction: UIEditMenuInteraction?
        private var dismissPanStartedWithSelection = false

        init(parent: SelectableTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            textView.invalidateIntrinsicContentSize()
            applySelectionStyle(to: textView)
            publishSelection(from: textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            applySelectionStyle(to: textView)
            publishSelection(from: textView)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            configureAncestorScrollViews(for: textView)
        }

        func makeInputAccessoryView() -> UIToolbar {
            let toolbar = UIToolbar()
            toolbar.sizeToFit()
            let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
            let done = UIBarButtonItem(
                title: L10n.done,
                style: .done,
                target: self,
                action: #selector(doneTapped)
            )
            toolbar.items = [flex, done]
            return toolbar
        }

        @objc func doneTapped() {
            textView?.resignFirstResponder()
        }

        @objc func handleKeyboardDismissPan(_ gesture: UIPanGestureRecognizer) {
            guard let textView, textView.isFirstResponder else { return }

            switch gesture.state {
            case .began:
                dismissPanStartedWithSelection = textView.selectedRange.length > 0
            case .changed:
                guard !dismissPanStartedWithSelection else { return }
                let translation = gesture.translation(in: textView)
                if translation.y > 12, abs(translation.y) > abs(translation.x) {
                    textView.resignFirstResponder()
                }
            default:
                break
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            gestureRecognizer === dismissPanRecognizer && otherGestureRecognizer.view is UIScrollView
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            if gestureRecognizer === dismissPanRecognizer {
                return textView?.isFirstResponder == true
            }
            return true
        }

        private func configureAncestorScrollViews(for view: UIView) {
            var ancestor: UIView? = view.superview
            while let current = ancestor {
                if let scrollView = current as? UIScrollView, scrollView !== view {
                    scrollView.keyboardDismissMode = .interactive
                }
                ancestor = current.superview
            }
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

        func applySelectionStyle(to textView: UITextView) {
            let plain = textView.text ?? ""
            let selectedRange = textView.selectedRange
            let attributed = NSMutableAttributedString(
                string: plain,
                attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .body),
                    .foregroundColor: UIColor.label,
                ]
            )

            if selectedRange.length > 0, NSMaxRange(selectedRange) <= attributed.length {
                attributed.addAttribute(
                    .backgroundColor,
                    value: UIColor.tintColor.withAlphaComponent(0.28),
                    range: selectedRange
                )
            }

            textView.textStorage.beginEditing()
            textView.textStorage.setAttributedString(attributed)
            textView.textStorage.endEditing()
            textView.selectedRange = selectedRange
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

    override func didMoveToWindow() {
        super.didMoveToWindow()
        configureAncestorScrollViews()
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            configureAncestorScrollViews()
        }
        return became
    }

    override var intrinsicContentSize: CGSize {
        let width = bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width - 64
        let fittingSize = sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: UIView.noIntrinsicMetric, height: max(minHeight, fittingSize.height))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        invalidateIntrinsicContentSize()
        configureAncestorScrollViews()
    }

    private func configureAncestorScrollViews() {
        var view: UIView? = superview
        while let ancestor = view {
            if let scrollView = ancestor as? UIScrollView, scrollView !== self {
                scrollView.keyboardDismissMode = .interactive
            }
            view = ancestor.superview
        }
    }
}

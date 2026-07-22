import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension View {
    /// 滚动时收起键盘（含 UIKit 文本框所在的 Form / List）。
    func dismissKeyboardOnScroll() -> some View {
        scrollDismissesKeyboard(.interactively)
            .background(FormScrollKeyboardDismissConfigurator())
    }
}

#if canImport(UIKit)
private struct FormScrollKeyboardDismissConfigurator: UIViewRepresentable {
    func makeUIView(context: Context) -> ConfiguratorView {
        ConfiguratorView()
    }

    func updateUIView(_ uiView: ConfiguratorView, context: Context) {
        uiView.configure()
    }

    final class ConfiguratorView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            configure()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            configure()
        }

        func configure() {
            var view: UIView? = self
            while let ancestor = view {
                if let scrollView = ancestor as? UIScrollView {
                    scrollView.keyboardDismissMode = .interactive
                }
                view = ancestor.superview
            }
        }
    }
}
#endif

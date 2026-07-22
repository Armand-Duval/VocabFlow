import SwiftUI

enum KeyboardDismiss {
    static func dismiss() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        #endif
    }
}

extension View {
    /// 在键盘上方显示「完成」按钮，用于多行输入框。
    func keyboardDoneButton() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(L10n.done) {
                    KeyboardDismiss.dismiss()
                }
            }
        }
    }
}

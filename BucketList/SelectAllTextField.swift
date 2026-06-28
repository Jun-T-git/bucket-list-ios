import SwiftUI
import UIKit

// A text field that selects all of its existing text the first time it gains
// focus, so an AI-suggested value can be overwritten by typing right away — no
// manual deletion. Also shows the standard clear (✕) button while editing.
// Used wherever a field is pre-filled with a suggestion (share sheet, add sheet).
struct SelectAllTextField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var font: UIFont = .preferredFont(forTextStyle: .body)
    var textColor: UIColor? = nil
    var autofocus: Bool = false
    var returnKey: UIReturnKeyType = .done
    var maxLength: Int? = nil
    var onBeganEditing: (() -> Void)? = nil
    var onReturn: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.placeholder = placeholder
        tf.delegate = context.coordinator
        tf.clearButtonMode = .whileEditing
        tf.returnKeyType = returnKey
        tf.font = font
        if let textColor { tf.textColor = textColor }
        tf.adjustsFontForContentSizeCategory = true
        tf.addTarget(context.coordinator,
                     action: #selector(Coordinator.editingChanged(_:)),
                     for: .editingChanged)
        tf.setContentHuggingPriority(.defaultLow, for: .horizontal)
        if autofocus {
            // Match the sheet's slide-in so the keyboard doesn't race the transition.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { tf.becomeFirstResponder() }
        }
        return tf
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        // 日本語などの未確定変換中（marked text あり）は text を書き換えない。
        // ここで代入すると変換セッションが壊れるため、確定後に同期する。
        if uiView.markedTextRange == nil, uiView.text != text { uiView.text = text }
        uiView.placeholder = placeholder
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        private let parent: SelectAllTextField
        private var didSelectAll = false
        init(_ parent: SelectAllTextField) { self.parent = parent }

        @objc func editingChanged(_ tf: UITextField) {
            let value = tf.text ?? ""
            // 未確定変換中（marked text あり）は切り詰めない。ここで tf.text を
            // 書き換えると日本語の変換が壊れるため、確定後の editingChanged で
            // 丸める。未確定の文字も含めてバインディングは同期しておく
            // （updateUIView 側でも marked 中は書き戻さないので食い違わない）。
            if tf.markedTextRange != nil {
                parent.text = value
                return
            }
            if let max = parent.maxLength, value.count > max {
                let capped = String(value.prefix(max))
                tf.text = capped   // keep the field and binding in sync at the cap
                parent.text = capped
            } else {
                parent.text = value
            }
        }

        func textFieldDidBeginEditing(_ tf: UITextField) {
            parent.onBeganEditing?()
            guard !didSelectAll else { return }
            didSelectAll = true
            // Defer so the selection sticks after focus settles.
            DispatchQueue.main.async { tf.selectAll(nil) }
        }

        func textFieldShouldReturn(_ tf: UITextField) -> Bool {
            if let onReturn = parent.onReturn { onReturn() } else { tf.resignFirstResponder() }
            return true
        }
    }
}

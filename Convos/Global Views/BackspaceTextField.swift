import SwiftUI
import UIKit

struct BackspaceTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var editingEnabled: Bool
    var onBackspaceWhenEmpty: () -> Void

    func makeUIView(context: Context) -> UITextField {
        let textField = BackspaceUITextField()
        textField.delegate = context.coordinator
        textField.onBackspaceWhenEmpty = onBackspaceWhenEmpty
        textField.font = UIFont.systemFont(ofSize: 14.0)
        textField.textColor = UIColor.colorTextPrimary
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, editingEnabled: $editingEnabled)
    }

    class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String
        @Binding var editingEnabled: Bool

        init(text: Binding<String>, editingEnabled: Binding<Bool>) {
            _text = text
            _editingEnabled = editingEnabled
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            return true
        }

        func textField(_ textField: UITextField,
                       shouldChangeCharactersIn range: NSRange,
                       replacementString string: String) -> Bool {
            guard editingEnabled else { return false }
            return true
        }

        func textFieldDidChangeSelection(_ textField: UITextField) {
            text = textField.text ?? ""
        }
    }
}

class BackspaceUITextField: UITextField {
    var onBackspaceWhenEmpty: (() -> Void)?

    override func deleteBackward() {
        if text?.isEmpty ?? true {
            onBackspaceWhenEmpty?()
        }
        super.deleteBackward()
    }
}

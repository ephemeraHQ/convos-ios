import SwiftUI
import UIKit

struct BackspaceTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var editingEnabled: Bool
    var onBackspaceWhenEmpty: () -> Void
    var onEndedEditing: () -> Void

    func makeUIView(context: Context) -> UITextField {
        let textField = BackspaceUITextField()
        textField.delegate = context.coordinator
        textField.onBackspaceWhenEmpty = onBackspaceWhenEmpty
        textField.font = UIFont.systemFont(ofSize: 16.0)
        textField.autocapitalizationType = .words
        textField.autocorrectionType = .no
        textField.textColor = UIColor.colorTextPrimary
        textField.tintColor = UIColor.colorTextPrimary
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
        Coordinator(
            text: $text,
            editingEnabled: $editingEnabled,
            onEndedEditing: onEndedEditing
        )
    }

    class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String
        @Binding var editingEnabled: Bool
        let onEndedEditing: (() -> Void)?

        init(text: Binding<String>,
             editingEnabled: Binding<Bool>,
             onEndedEditing: (() -> Void)?) {
            _text = text
            _editingEnabled = editingEnabled
            self.onEndedEditing = onEndedEditing
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            return true
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            Log.info("Started editing textfield")
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            Log.info("Ended editing textfield")
            onEndedEditing?()
        }

        func textField(_ textField: UITextField,
                       shouldChangeCharactersIn range: NSRange,
                       replacementString string: String) -> Bool {
            guard editingEnabled else { return false }
            return true
        }

        func textFieldDidChangeSelection(_ textField: UITextField) {
            DispatchQueue.main.async { [weak self] in
                self?.text = textField.text ?? ""
            }
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

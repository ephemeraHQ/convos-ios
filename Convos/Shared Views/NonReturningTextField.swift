import SwiftUI

struct NonReturningTextField: UIViewRepresentable {
    var placeholderText: String
    @Binding var text: String
    var onReturn: () -> Void

    init(_ placeholderText: String, text: Binding<String>, onReturn: @escaping () -> Void) {
        self.placeholderText = placeholderText
        self._text = text
        self.onReturn = onReturn
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.placeholder = placeholderText
        textField.delegate = context.coordinator
        textField.returnKeyType = .done
        textField.autocapitalizationType = .words
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        uiView.text = text
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: NonReturningTextField

        init(_ parent: NonReturningTextField) {
            self.parent = parent
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onReturn()
            return false // Don't dismiss keyboard
        }

        func textFieldDidChangeSelection(_ textField: UITextField) {
            parent.text = textField.text ?? ""
        }
    }
}

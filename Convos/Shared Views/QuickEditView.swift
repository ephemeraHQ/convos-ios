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

struct QuickEditView: View {
    let placeholderText: String
    @Binding var text: String
    @Binding var image: UIImage?
    @FocusState.Binding var focusState: MessagesViewInputFocus?
    let focused: MessagesViewInputFocus
    let onSubmit: () -> Void
    let onSettings: () -> Void

    var body: some View {
        HStack {
            ImagePickerButton(currentImage: $image)
                .frame(width: 52.0, height: 52.0)

            NonReturningTextField(
                placeholderText,
                text: $text,
                onReturn: onSubmit
            )
            .padding(.horizontal, 16.0)
            .font(.system(size: 17.0))
            .tint(.colorTextPrimary)
            .foregroundStyle(.colorTextPrimary)
            .multilineTextAlignment(.center)
            .textInputAutocapitalization(.words)
            .truncationMode(.tail)
            .focused($focusState, equals: focused)
            .submitLabel(.done)
            .frame(minWidth: 166.0, maxWidth: 180.0)
            .frame(height: 52.0)
            .background(
                Capsule()
                    .stroke(.gray.opacity(0.2), lineWidth: 1.0)
            )

            Button {
                onSettings()
            } label: {
                Image(systemName: "gear")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.black.opacity(0.3))
                    .padding(.horizontal, 12.0)
            }
            .frame(width: 52.0, height: 52.0)
            .background(Circle().fill(.gray.opacity(0.2)))
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    @Previewable @State var text: String = ""
    @Previewable @State var image: UIImage?
    @Previewable @FocusState var focusState: MessagesViewInputFocus?
    QuickEditView(
        placeholderText: "New convo",
        text: $text,
        image: $image,
        focusState: $focusState,
        focused: .displayName,
    ) {
    } onSettings: {
    }
}

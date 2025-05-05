import SwiftUI

struct ContactCardView: View {
    @Binding var name: String
    @Binding var imageState: ContactCardImage.State
    @Binding var nameIsValid: Bool
    @Binding var nameError: String?
    @Binding var isEditing: Bool
    @FocusState.Binding var isNameFocused: Bool

    let importAction: () -> Void

    var body: some View {
        VStack(spacing: 10.0) {
            HStack(alignment: .top) {
                ContactCardAvatarView(isEditing: $isEditing, imageState: $imageState) {
                    MonogramView(name: name)
                }

                Spacer()

//                if isEditing {
//                    Button {
//                        importAction()
//                    } label: {
//                        Text("Import")
//                            .font(DesignConstants.Fonts.buttonText)
//                            .foregroundStyle(Color.colorFillSecondary)
//                            .padding(.horizontal, DesignConstants.Spacing.step3x)
//                            .padding(.vertical, DesignConstants.Spacing.step2x)
//                    }
//                }
            }

            ZStack {
                LabeledTextField(label: "Name",
                                 prompt: "Nice to meet you",
                                 textFieldBorderColor: nameError == nil ? .colorBorderSubtle : .colorCaution,
                                 text: $name,
                                 isFocused: $isNameFocused)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .opacity(isEditing ? 1.0 : 0.0)
                    .transition(.scale)

                if !isEditing {
                    HStack {
                        Text(name)
                            .font(.title.bold())
                            .foregroundStyle(.colorTextPrimary)

                        Spacer()
                    }
                }
            }
            .environment(\.colorScheme, .dark)
        }
        .padding(DesignConstants.Spacing.medium)
        .background(.backgroundSurface)
        .clipShape(RoundedRectangle(cornerRadius: DesignConstants.CornerRadius.regular))
        .shadow(color: .colorDarkAlpha15, radius: 8, x: 0, y: 4)
        .animation(.easeInOut(duration: 0.3), value: isEditing)
    }
}

#Preview {
    @Previewable @State var imageState: ContactCardImage.State = .empty
    @Previewable @State var name = "Robert Adams"
    @Previewable @State var nameIsValid = true
    @Previewable @State var nameError: String?
    @Previewable @State var isEditing = false
    @Previewable @FocusState var isNameFocused: Bool

    VStack {
        ContactCardView(name: $name,
                        imageState: $imageState,
                        nameIsValid: $nameIsValid,
                        nameError: $nameError,
                        isEditing: $isEditing,
                        isNameFocused: $isNameFocused,
                        importAction: {})

        Button(isEditing ? "Done" : "Edit") {
            isEditing.toggle()
        }
        .padding()
    }
}

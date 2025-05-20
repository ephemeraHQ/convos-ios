import SwiftUI

struct ProfileView: View {
    @Binding var name: String
    @Binding var imageState: ContactCardImage.State
    @Binding var nameIsValid: Bool
    @Binding var nameError: String?
    @Binding var isEditing: Bool

    @FocusState var isNameFocused: Bool
    @State private var hasAppeared: Bool = false
    @State private var isVisible: Bool = true

    var body: some View {
        VStack {
            Spacer()
                .frame(height: DesignConstants.Spacing.step12x)
            DraggableSpringyView {
                ContactCardView(name: $name,
                                imageState: $imageState,
                                nameIsValid: $nameIsValid,
                                nameError: $nameError,
                                isEditing: $isEditing,
                                isNameFocused: $isNameFocused,
                                importAction: {
                    //                importCardAction()
                })
            }
            .zIndex(1)

            Spacer()

            Button("Sign out") {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isNameFocused = false
                    isEditing = false
                }
            }
            .convosButtonStyle(.outline(fullWidth: true))
            .padding(.horizontal, DesignConstants.Spacing.step3x)
            .padding(.bottom, DesignConstants.Spacing.step3x)
            .zIndex(0)
        }
        .opacity(isVisible ? 1.0 : 0.0)
        .padding(.horizontal, DesignConstants.Spacing.step3x)
        .background(.colorBackgroundPrimary)
        .animation(.easeInOut(duration: 0.3), value: isNameFocused)
        .animation(.easeInOut(duration: 0.2), value: hasAppeared)
        .animation(.easeInOut(duration: 0.2), value: isEditing)
        .onAppear {
            hasAppeared = true
        }
    }
}

#Preview {
    @Previewable @State var name = "Bob Adams"
    @Previewable @State var imageState: ContactCardImage.State = .empty
    @Previewable @State var nameIsValid = false
    @Previewable @State var isEditing = false
    @Previewable @State var nameError: String?

    ProfileView(name: $name,
                imageState: $imageState,
                nameIsValid: $nameIsValid,
                nameError: $nameError,
                isEditing: $isEditing
    )
}

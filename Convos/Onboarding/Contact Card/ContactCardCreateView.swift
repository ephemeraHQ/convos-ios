import SwiftUI

struct ContactCardCreateView: View {
    @Binding var name: String
    @Binding var imageState: ContactCardImage.State
    @Binding var nameIsValid: Bool
    @Binding var nameError: String?
    @Binding var isEditing: Bool

    let importCardAction: () -> Void
    let submitAction: () -> Void

    @FocusState var isNameFocused: Bool
    @State private var hasAppeared: Bool = false
    @State private var isVisible: Bool = true

    @Environment(\.dismiss) var dismiss: DismissAction

    var body: some View {
        VStack(spacing: DesignConstants.Spacing.medium) {
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .convosButtonStyle(.text)

                Spacer()
            }
            .padding(.top, DesignConstants.Spacing.step3x)
            .opacity(isEditing ? 1.0 : 0.0)

            Spacer(minLength: 0.0)

            VStack(spacing: DesignConstants.Spacing.medium) {
                if !isNameFocused, hasAppeared, isEditing {
                    VStack(spacing: DesignConstants.Spacing.small) {
                        Text("Complete your contact card")
                            .font(.largeTitle.bold())
                            .multilineTextAlignment(.center)
                            .padding(.top, DesignConstants.Spacing.step6x)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Choose how you show up")
                            .font(.body)
                            .foregroundColor(.primary)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                DraggableSpringyView {
                    ContactCardEditView(
                        name: $name,
                        imageState: $imageState,
                        nameIsValid: $nameIsValid,
                        nameError: $nameError,
                        isEditing: $isEditing,
                        isNameFocused: $isNameFocused,
                        importAction: {
                            importCardAction()
                        }
                    )
                }
                .zIndex(1)
                .overlay(alignment: .bottom) {
                    if let nameError {
                        Text(nameError)
                            .font(.subheadline)
                            .foregroundStyle(.colorCaution)
                            .multilineTextAlignment(.center)
                            .offset(y: DesignConstants.Spacing.step10x)
                    }
                }
                .rotation3DEffect(
                    .degrees(hasAppeared ? 0.0 : 15.0),
                    axis: (x: 1.0, y: 0.0, z: 0.0)
                )
                .offset(y: hasAppeared ? 0.0 : 40.0)
                .animation(.spring(duration: 0.6, bounce: 0.5).delay(0.1), value: hasAppeared)

                if !isNameFocused, hasAppeared, nameError == nil {
                    Text(isEditing ? "You can update this anytime." : "Looks good!")
                        .font(.subheadline)
                        .foregroundStyle(Color.colorTextSecondary)
                        .padding(.bottom, DesignConstants.Spacing.step6x)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(0)
                }
            }
            .padding(.horizontal, DesignConstants.Spacing.step3x)

            Spacer(minLength: 0.0)

            Button("That's me") {
                // temporary animation
                withAnimation(.easeInOut(duration: 0.3)) {
                    isNameFocused = false
                    isEditing = false
                }

                submitAction()
            }
            .convosButtonStyle(.outline(fullWidth: true))
            .opacity(isEditing ? 1.0 : 0.0)
            .disabled(!nameIsValid)
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
    @Previewable @State var name = ""
    @Previewable @State var imageState: ContactCardImage.State = .empty
    @Previewable @State var nameIsValid = false
    @Previewable @State var isEditing = true
    @Previewable @State var nameError: String?
    ContactCardCreateView(
        name: $name,
        imageState: $imageState,
        nameIsValid: $nameIsValid,
        nameError: $nameError,
        isEditing: $isEditing,
        importCardAction: {
            // Placeholder for import card action
        },
        submitAction: {
            // Placeholder for submit action
        }
    )
}

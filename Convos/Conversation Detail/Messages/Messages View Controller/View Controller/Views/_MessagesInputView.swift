import PhotosUI
import SwiftUI

struct __MessagesInputView: View {
    enum FocusField {
        case profileName, messageText
    }

    @Binding var text: String
    @Binding var sendButtonEnabled: Bool
    @Binding var profile: Profile
    @Binding var profileName: String
    @FocusState var focusedField: FocusField?
    let textDidChange: (String) -> Void
    let onSend: () -> Void

    @Namespace private var profileEditorAnimation: Namespace.ID
    @State private var showingProfileNameEditor: Bool = false

    var body: some View {
        Group {
            if showingProfileNameEditor {
                profileNameEditor
            } else {
                inputBarView
            }
        }
    }

    // MARK: - Profile Name Editor

    @State private var imageSelection: PhotosPickerItem?

    @ViewBuilder
    private var profileNameEditor: some View {
        HStack {
            HStack {
                PhotosPicker(
                    selection: $imageSelection,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label("Photo Picker", systemImage: "photo.on.rectangle.angled")
                        .tint(.white)
                        .labelStyle(.iconOnly)
                        .frame(width: 50, height: 50)
                        .background(Circle().fill(.gray))
                        .foregroundColor(.white)
                }
                .matchedGeometryEffect(
                    id: "button",
                    in: profileEditorAnimation
                )
                .padding()

                TextField(profile.displayName, text: $profileName)
                    .focused($focusedField, equals: .profileName)
                    .matchedGeometryEffect(id: "text", in: profileEditorAnimation)
            }
            .glassEffect(.regular, in: .rect(cornerRadius: 20.0))
            .padding(DesignConstants.Spacing.stepX)
            .matchedGeometryEffect(
                id: "container",
                in: profileEditorAnimation,
                isSource: false
            )

            Spacer()

            Button {
                withAnimation {
                    showingProfileNameEditor = false
                }
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(.colorTextSecondary)
                    .font(.body)
                    .frame(minWidth: addButtonSize,
                           minHeight: addButtonSize)
                    .padding(.vertical, buttonVerticalPadding)
                    .padding(.horizontal, 7.0)
            }
            .aspectRatio(1.0, contentMode: .fill)
            .glassEffect(.regular, in: .circle)
            .padding(DesignConstants.Spacing.stepX)
        }
        .padding(.horizontal, 10.0)
        .padding(.vertical, 6.0)
        .frame(maxWidth: .infinity)
        .background(.clear)
    }

    // MARK: - Input Bar

    @State private var textEditorHeight: CGFloat = 0
    private let maxCapsuleHeight: CGFloat = 40.0

    var textClipShape: some Shape {
        textEditorHeight <= maxCapsuleHeight ?
        AnyShape(Capsule()) :
        AnyShape(RoundedRectangle(cornerRadius: maxCapsuleHeight / 2.0))
    }

    var buttonVerticalPadding: CGFloat {
        DesignConstants.Spacing.step2x
    }

    var addButtonSize: CGFloat {
        maxCapsuleHeight - (buttonVerticalPadding * 2.0)
    }

    var sendButtonSize: CGFloat {
        maxCapsuleHeight - DesignConstants.Spacing.step2x
    }

    @ViewBuilder
    private var inputBarView: some View {
        HStack(alignment: .bottom, spacing: 0.0) {
            Button {
            } label: {
                Image(systemName: "plus")
                    .foregroundStyle(.colorTextSecondary)
                    .font(.body)
                    .frame(minWidth: addButtonSize,
                           minHeight: addButtonSize)
                    .padding(.vertical, buttonVerticalPadding)
                    .padding(.horizontal, 7.0)
            }
            .aspectRatio(1.0, contentMode: .fill)
            .glassEffect(.regular, in: .circle)
            .padding(DesignConstants.Spacing.stepX)

            HStack(alignment: .bottom, spacing: 0.0) {
                Button {
                    withAnimation {
                        showingProfileNameEditor = true
                    }
                } label: {
                    ProfileAvatarView(profile: profile)
                }
                .frame(width: sendButtonSize,
                       height: sendButtonSize)
                .padding(.vertical, DesignConstants.Spacing.stepX)
                .padding(.leading, DesignConstants.Spacing.stepX)
                .matchedGeometryEffect(
                    id: "button",
                    in: profileEditorAnimation
                )

                ZStack {
                    TextEditor(text: $text)
                        .font(.body)
                        .foregroundStyle(.colorTextPrimary)
                        .lineLimit(5)
                        .textEditorStyle(.plain)
                        .tint(.colorTextPrimary)
                        .background(
                            GeometryReader { geometry in
                                Color.clear.onAppear {
                                    textEditorHeight = geometry.size.height
                                }
                                .onChange(of: geometry.size.height) {
                                    textEditorHeight = geometry.size.height
                                }
                            }
                        )
                        .onChange(of: text) {
                            textDidChange(text)
                        }
                        .focused($focusedField, equals: .messageText)

                    if text.isEmpty {
                        HStack(alignment: .center) {
                            Text("Chat as \(profile.displayName)")
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 5)

                            Spacer()
                        }
                    }
                }
                .frame(minHeight: maxCapsuleHeight)
                .padding(.horizontal, DesignConstants.Spacing.step3x)
                .fixedSize(horizontal: false, vertical: true)
                .matchedGeometryEffect(id: "text", in: profileEditorAnimation)

                Button {
                    onSend()
                } label: {
                    Image(systemName: "arrow.up")
                        .tint(.colorTextPrimary)
                        .font(.caption.weight(.medium))
                        .frame(minWidth: sendButtonSize,
                               minHeight: sendButtonSize)
                }
                .glassEffect(in: .circle)
                .padding(.vertical, DesignConstants.Spacing.stepX)
                .padding(.trailing, DesignConstants.Spacing.stepX)
                .disabled(!sendButtonEnabled)
            }
            .glassEffect(.regular, in: textClipShape)
            .padding(DesignConstants.Spacing.stepX)
            .matchedGeometryEffect(
                id: "container",
                in: profileEditorAnimation,
                isSource: true
            )
        }
        .padding(.horizontal, 10.0)
        .padding(.vertical, 6.0)
        .frame(maxWidth: .infinity)
        .background(.clear)
        .defaultFocus($focusedField, .messageText)
    }
}

#Preview {
    @Previewable @State var text: String = ""
    @Previewable @State var sendButtonEnabled: Bool = false
    @Previewable @State var profile: Profile = .mock()
    @Previewable @State var profileName: String = ""

    __MessagesInputView(
        text: $text,
        sendButtonEnabled: $sendButtonEnabled,
        profile: $profile,
        profileName: $profileName,
        textDidChange: { _ in },
        onSend: {}
    )
}

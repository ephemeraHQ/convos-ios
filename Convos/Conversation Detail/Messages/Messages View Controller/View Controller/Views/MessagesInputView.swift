import PhotosUI
import SwiftUI

@Observable
class MessagesInputViewModel: KeyboardListenerDelegate {
    let conversationState: ConversationState
    let outgoingMessageWriter: any OutgoingMessageWriterProtocol

    init(
        conversationState: ConversationState,
        outgoingMessageWriter: any OutgoingMessageWriterProtocol,
        profile: Profile
    ) {
        self.profile = profile
        self.profileNameText = profile.displayName
        self.conversationState = conversationState
        self.outgoingMessageWriter = outgoingMessageWriter

        KeyboardListener.shared.add(delegate: self)
    }

    deinit {
        KeyboardListener.shared.remove(delegate: self)
    }

    func keyboardWillHide(info: KeyboardInfo) {
        withAnimation {
            showingProfileNameEditor = false
        }
    }

    var messageText: String = "" {
        didSet {
            let conversationHasMembers: Bool = !(conversationState.conversation?.members.isEmpty ?? true)
            sendButtonEnabled = !messageText.isEmpty && conversationHasMembers
        }
    }
    var profileNameText: String
    var profileNamePlaceholder: String = "Somebody"
    var sendButtonEnabled: Bool = false
    var showingProfileNameEditor: Bool = false
    var profile: Profile {
        didSet {
            profileNamePlaceholder = profile.displayName.isEmpty ? "Somebody" : profile.displayName
        }
    }
    var imageSelection: PhotosPickerItem?

    func sendMessage() {
        let prevMessageText = messageText
        messageText = ""
        Task { [outgoingMessageWriter] in
            do {
                try await outgoingMessageWriter.send(text: prevMessageText)
            } catch {
                Logger.error("Error sending message: \(error)")
            }
        }
    }

    func saveProfileName() {
        // @jarodl update profile on convos backend
        profile = .init(
            inboxId: profile.inboxId,
            name: profileNameText,
            username: profile.username,
            avatar: profile.avatar
        )

        withAnimation {
            showingProfileNameEditor = false
        }
    }
}

struct MessagesInputView: View {
    @State var viewModel: MessagesInputViewModel
    @State private var textEditorHeight: CGFloat = 0
    private let maxCapsuleHeight: CGFloat = 46.0

    private var textClipShape: some Shape {
        if viewModel.showingProfileNameEditor {
            AnyShape(RoundedRectangle(cornerRadius: 40.0))
        } else if textEditorHeight <= maxCapsuleHeight {
            AnyShape(Capsule())
        } else {
            AnyShape(RoundedRectangle(cornerRadius: maxCapsuleHeight / 2.0))
        }
    }

    private var buttonVerticalPadding: CGFloat {
        DesignConstants.Spacing.step2x
    }

    private var addButtonSize: CGFloat {
        maxCapsuleHeight - (buttonVerticalPadding * 2.0)
    }

    private var sendButtonSize: CGFloat {
        maxCapsuleHeight - DesignConstants.Spacing.step2x
    }

    @Namespace private var profileEditorAnimation: Namespace.ID
    @State private var mode: DualTextView.Mode = .textView

    var body: some View {
        HStack(alignment: .bottom) {
            if viewModel.showingProfileNameEditor {
                // empty
            } else {
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
            }

            HStack(alignment: .bottom, spacing: 0) {
                if viewModel.showingProfileNameEditor {
                    PhotosPicker(
                        selection: $viewModel.imageSelection,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 24.0))
                            .padding(.vertical, 7.5)
                            .padding(.horizontal, 14.0)
                            .foregroundColor(.white)
                    }
                    .frame(width: 52.0, height: 52.0, alignment: .center)
                    .background(Circle().fill(.gray))
//                    .matchedGeometryEffect(
//                        id: "LeftView",
//                        in: profileEditorAnimation
//                    )
                    .padding([.leading, .vertical], DesignConstants.Spacing.step6x)
                    .padding(.trailing, 0.0)
                } else {
                    Button {
                        withAnimation {
                            viewModel.showingProfileNameEditor = true
                        }
                    } label: {
                        ProfileAvatarView(profile: viewModel.profile)
                    }
                    .frame(height: sendButtonSize, alignment: .center)
//                    .matchedGeometryEffect(
//                        id: "LeftView",
//                        in: profileEditorAnimation
//                    )
                    .padding(.vertical, DesignConstants.Spacing.stepX)
                    .padding(.leading, DesignConstants.Spacing.stepX)
                    .frame(height: sendButtonSize, alignment: .bottomLeading)
                }

                Group {
                    DualTextViewRepresentable(
                        textViewText: $viewModel.messageText,
                        textFieldText: $viewModel.profileNameText,
                        mode: $mode,
                        height: $textEditorHeight,
                        textViewPlaceholder: "Chat as \(viewModel.profileNamePlaceholder)",
                        textFieldPlaceholder: "Somebody...",
                        font: .systemFont(ofSize: 16.0),
                        textColor: .colorTextPrimary,
                        textFieldShouldReturn: { _ in
                            viewModel.saveProfileName()
                            return true
                        }
                    )
                    .frame(height: textEditorHeight)
                    .frame(maxWidth: .infinity, minHeight: 20.0, alignment: .center)
                    .padding(.horizontal, viewModel.showingProfileNameEditor ? 20.0 : DesignConstants.Spacing.step3x)
                    .padding(
                        .vertical,
                        viewModel.showingProfileNameEditor ? DesignConstants.Spacing.step4x : DesignConstants.Spacing
                            .step2x
                    )
                    .background(
                        RoundedRectangle(cornerRadius: DesignConstants.CornerRadius.mediumLarge)
                            .fill(viewModel.showingProfileNameEditor ? .colorFillMinimal : .clear)
                    )
                }
                .padding(.horizontal, viewModel.showingProfileNameEditor ? DesignConstants.Spacing.step2x : 0.0)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                if viewModel.showingProfileNameEditor {
                    Button {
                        withAnimation {
                            viewModel.showingProfileNameEditor = false
                        }
                    } label: {
                        Image(systemName: "gear")
                            .foregroundStyle(.colorTextSecondary)
                            .font(.system(size: 24.0))
                            .padding(.vertical, 7.5)
                            .padding(.horizontal, 14.0)
                            .frame(width: 52.0, height: 52.0, alignment: .center)
                            .background(.colorFillMinimal)
                            .mask(Circle())
                    }
//                    .matchedGeometryEffect(
//                        id: "RightView",
//                        in: profileEditorAnimation
//                    )
                    .padding([.trailing, .vertical], DesignConstants.Spacing.step6x)
                } else {
                    Button {
                        viewModel.sendMessage()
                    } label: {
                        Image(systemName: "arrow.up")
                            .tint(.colorTextPrimary)
                            .font(.system(size: 16.0, weight: .medium))
                            .padding()
                            .frame(height: sendButtonSize, alignment: .center)
                            .background(.colorFillMinimal)
                            .mask(Circle())
                    }
//                    .matchedGeometryEffect(
//                        id: "RightView",
//                        in: profileEditorAnimation
//                    )
                    .frame(maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.vertical, DesignConstants.Spacing.stepX)
                    .disabled(!viewModel.sendButtonEnabled)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(DesignConstants.Spacing.stepX)
            .glassEffect(.regular, in: textClipShape)
        }
        .padding(.horizontal, 10.0)
        .padding(.vertical, DesignConstants.Spacing.step2x)
        .frame(maxWidth: .infinity, alignment: .bottom)
        .fixedSize(horizontal: false, vertical: true)
        .background(.clear)
        .onChange(of: viewModel.showingProfileNameEditor) {
            withAnimation {
                if viewModel.showingProfileNameEditor {
                    mode = .textField
                } else {
                    mode = .textView
                }
            }
        }
    }
}

#Preview {
    MessagesInputView(
        viewModel: .init(
            conversationState: .init(conversationRepository: MockConversationRepository()),
            outgoingMessageWriter: MockOutgoingMessageWriter(),
            profile: .mock()
        ),
    )
}

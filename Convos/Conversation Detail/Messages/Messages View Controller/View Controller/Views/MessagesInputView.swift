import PhotosUI
import SwiftUI
import UIKit

@Observable
class MessagesInputViewModel: KeyboardListenerDelegate {
    let myProfileWriter: any MyProfileWriterProtocol
    let outgoingMessageWriter: any OutgoingMessageWriterProtocol

    init(
        myProfileWriter: any MyProfileWriterProtocol,
        outgoingMessageWriter: any OutgoingMessageWriterProtocol,
    ) {
        self.myProfileWriter = myProfileWriter
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
            sendButtonEnabled = !messageText.isEmpty
        }
    }
    var profileNameText: String = ""
    var profileNamePlaceholder: String = "Somebody"
    var sendButtonEnabled: Bool = false
    var showingProfileNameEditor: Bool = false
    var showingPhotosPicker: Bool = false
    var avatarImage: Image?
    var imageSelection: UIImage? {
        didSet {
            if let image = imageSelection {
                handleImageSelection(image)
            }
        }
    }

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
        Task {
            do {
                try await myProfileWriter.update(displayName: profileNameText)
            } catch {
                Logger.error("Error saving profile name: \(error)")
            }
        }

        withAnimation {
            showingProfileNameEditor = false
        }
    }

    private func handleImageSelection(_ image: UIImage) {
        // Update the avatar image for display
        avatarImage = Image(uiImage: image)

        Task {
            do {
                try await myProfileWriter.update(avatar: image)
            } catch {
                Logger.error("Error updating profile photo: \(error.localizedDescription)")
            }
        }
    }
}

struct MessagesInputView: View {
    @State var viewModel: MessagesInputViewModel
    @State var conversationState: ConversationState
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
//            if viewModel.showingProfileNameEditor {
//                EmptyView()
//                    .matchedGeometryEffect(
//                        id: "AddButton",
//                        in: profileEditorAnimation,
//                    )
//            } else {
//                Button {
//                } label: {
//                    Image(systemName: "plus")
//                        .foregroundStyle(.colorTextSecondary)
//                        .font(.body)
//                        .frame(width: addButtonSize, height: addButtonSize)
//                        .padding(.vertical, buttonVerticalPadding)
//                        .padding(.horizontal, 7.0)
//                }
//                .glassEffect(.regular, in: .circle)
//                .matchedGeometryEffect(
//                    id: "AddButton",
//                    in: profileEditorAnimation,
//                )
//                .padding(DesignConstants.Spacing.stepX)
//            }

            HStack(alignment: .bottom, spacing: 0) {
                if viewModel.showingProfileNameEditor {
                    Button {
                        viewModel.showingPhotosPicker = true
                    } label: {
                        Image(systemName: "photo.on.rectangle.fill")
                            .frame(width: 52.0, height: 52.0)
                            .font(.system(size: 24.0))
                            .padding(.vertical, 7.5)
                            .padding(.horizontal, 14.0)
                            .foregroundColor(.white)
                    }
                    .frame(width: 52.0, height: 52.0)
                    .background(.colorFillSecondary)
                    .mask(Circle())
                    .matchedGeometryEffect(
                        id: "LeftView",
                        in: profileEditorAnimation,
                    )
                    .padding([.leading, .vertical], DesignConstants.Spacing.step6x)
                    .padding(.trailing, 0.0)
                } else {
                    Button {
                        withAnimation {
                            viewModel.showingProfileNameEditor = true
                        }
                    } label: {
                        ProfileAvatarView(profile: conversationState.myProfile)
                            .frame(width: sendButtonSize, height: sendButtonSize)
                            .matchedGeometryEffect(
                                id: "LeftView",
                                in: profileEditorAnimation,
                            )
                    }
                    .frame(alignment: .bottomLeading)
                    .padding(.vertical, DesignConstants.Spacing.stepX)
                    .padding(.leading, DesignConstants.Spacing.stepX)
                }

                Group {
                    DualTextViewRepresentable(
                        textViewText: $viewModel.messageText,
                        textFieldText: $viewModel.profileNameText,
                        mode: $mode,
                        height: $textEditorHeight,
                        textViewPlaceholder: "Chat as \(conversationState.myProfile.displayName)",
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
                        }
                    } label: {
                        Image(systemName: "gear")
                            .frame(width: 52.0, height: 52.0)
                            .foregroundStyle(.colorTextSecondary)
                            .font(.system(size: 24.0))
                            .padding(.vertical, 7.5)
                            .padding(.horizontal, 14.0)
                    }
                    .disabled(true)
                    .frame(width: 52.0, height: 52.0)
                    .background(.colorFillMinimal)
                    .mask(Circle())
                    .matchedGeometryEffect(
                        id: "RightView",
                        in: profileEditorAnimation
                    )
                    .padding([.trailing, .vertical], DesignConstants.Spacing.step6x)
                } else {
                    Button {
                        viewModel.sendMessage()
                    } label: {
                        Image(systemName: "arrow.up")
                            .frame(width: sendButtonSize, height: sendButtonSize, alignment: .center)
                            .tint(.colorTextPrimary)
                            .font(.system(size: 16.0, weight: .medium))
                    }
                    .background(.colorFillMinimal)
                    .mask(Circle())
                    .matchedGeometryEffect(
                        id: "RightView",
                        in: profileEditorAnimation
                    )
                    .frame(width: sendButtonSize, height: sendButtonSize, alignment: .bottomLeading)
                    .padding(.vertical, DesignConstants.Spacing.stepX)
                    .padding(.trailing, DesignConstants.Spacing.stepX)
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
        .background(
            GeometryReader { geometry in
                Color.clear
                    .preference(
                        key: HeightPreferenceKey.self,
                        value: geometry.size.height
                    )
            }
        )
    }
}

#Preview {
    let messagingService = MockMessagingService()
    MessagesInputView(
        viewModel: .init(
            myProfileWriter: messagingService,
            outgoingMessageWriter: MockOutgoingMessageWriter()
        ),
        conversationState: .init(
            myProfileRepository: messagingService,
            conversationRepository: MockConversationRepository()
        )
    )
}

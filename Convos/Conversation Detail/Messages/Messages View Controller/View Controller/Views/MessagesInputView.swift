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
    let profile: Profile
    @Binding var profileImage: UIImage?
    @Binding var displayName: String
    let emptyDisplayNamePlaceholder: String
    @Binding var messageText: String
    @Binding var sendButtonEnabled: Bool
    var focusState: FocusState<MessagesViewInputFocus?>.Binding
    private let focused: MessagesViewInputFocus = .message
    let onProfilePhotoTap: () -> Void
    let onSendMessage: () -> Void
    private let maxCapsuleHeight: CGFloat = 46.0

    private var buttonVerticalPadding: CGFloat {
        DesignConstants.Spacing.step2x
    }

    private var sendButtonSize: CGFloat {
        maxCapsuleHeight - DesignConstants.Spacing.step2x
    }

    var body: some View {
        HStack(alignment: .bottom) {
            HStack(alignment: .bottom, spacing: 0) {
                Button {
                    onProfilePhotoTap()
                } label: {
                    AvatarView(
                        imageURL: profile.avatarURL,
                        fallbackName: profile.displayName,
                        cacheableObject: nil,
                        cachedImage: profileImage
                    )
                    .frame(width: sendButtonSize, height: sendButtonSize)
                }
                .frame(alignment: .bottomLeading)
                .padding(.vertical, DesignConstants.Spacing.stepX)
                .padding(.leading, DesignConstants.Spacing.stepX)

                Group {
                    TextField(
                        "Chat as \(displayName.isEmpty ? emptyDisplayNamePlaceholder : displayName)",
                        text: $messageText,
                        axis: .vertical
                    )
                    .focused(focusState, equals: focused)
                    .foregroundStyle(.colorTextPrimary)
                    .tint(.colorTextPrimary)
                    .frame(maxWidth: .infinity, minHeight: 20.0, alignment: .center)
                    .padding(.horizontal, DesignConstants.Spacing.step3x)
                    .padding(.vertical, DesignConstants.Spacing.step2x)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                Button {
                    onSendMessage()
                } label: {
                    Image(systemName: "arrow.up")
                        .frame(width: sendButtonSize, height: sendButtonSize, alignment: .center)
                        .tint(.colorTextPrimary)
                        .font(.system(size: 16.0, weight: .medium))
                }
                .background(.colorFillMinimal)
                .mask(Circle())
                .frame(width: sendButtonSize, height: sendButtonSize, alignment: .bottomLeading)
                .padding(.vertical, DesignConstants.Spacing.stepX)
                .padding(.trailing, DesignConstants.Spacing.stepX)
                .disabled(!sendButtonEnabled)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(DesignConstants.Spacing.stepX)
        }
        .frame(maxWidth: .infinity, alignment: .bottom)
        .fixedSize(horizontal: false, vertical: true)
        .background(.clear)
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
    @Previewable @State var profile: Profile = .mock()
    @Previewable @State var displayName: String = "Andrew"
    @Previewable @State var messageText: String = ""
    @Previewable @State var sendButtonEnabled: Bool = false
    @Previewable @State var profileImage: UIImage?
    @Previewable @FocusState var focusState: MessagesViewInputFocus?

    MessagesInputView(
        profile: profile,
        profileImage: $profileImage,
        displayName: $displayName,
        emptyDisplayNamePlaceholder: "Somebody",
        messageText: $messageText,
        sendButtonEnabled: $sendButtonEnabled,
        focusState: $focusState) {
        } onSendMessage: {
        }
}

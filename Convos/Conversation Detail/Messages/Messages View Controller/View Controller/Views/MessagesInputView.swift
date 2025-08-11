import PhotosUI
import SwiftUI
import UIKit

struct MessagesInputView: View {
    let profile: Profile
    @Binding var profileImage: UIImage?
    @Binding var displayName: String
    let emptyDisplayNamePlaceholder: String
    @Binding var messageText: String
    @Binding var sendButtonEnabled: Bool
    @FocusState.Binding var focusState: MessagesViewInputFocus?
    private let focused: MessagesViewInputFocus = .message
    let onProfilePhotoTap: () -> Void
    let onSendMessage: () -> Void

    static var defaultHeight: CGFloat {
        32.0
    }

    private var sendButtonSize: CGFloat {
        Self.defaultHeight
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            Button {
                onProfilePhotoTap()
            } label: {
                ProfileAvatarView(profile: profile)
            }
            .frame(width: sendButtonSize, height: sendButtonSize)
            .frame(alignment: .bottomLeading)

            Group {
                TextField(
                    "Chat as \(displayName.isEmpty ? emptyDisplayNamePlaceholder : displayName)",
                    text: $messageText,
                    axis: .vertical
                )
                .focused($focusState, equals: focused)
                .font(.system(size: 16.0))
                .foregroundStyle(.colorTextPrimary)
                .tint(.colorTextPrimary)
                .frame(maxWidth: .infinity, minHeight: Self.defaultHeight, alignment: .center)
                .padding(.horizontal, DesignConstants.Spacing.step3x)
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
            .disabled(!sendButtonEnabled)
        }
        .padding(DesignConstants.Spacing.step2x)
        .frame(maxWidth: .infinity, alignment: .bottom)
        .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    @Previewable @State var profile: Profile = .mock()
    @Previewable @State var displayName: String = "Andrew"
    @Previewable @State var messageText: String = ""
    @Previewable @State var sendButtonEnabled: Bool = false
    @Previewable @State var profileImage: UIImage?
    @Previewable @FocusState var focusState: MessagesViewInputFocus?

    VStack {
        Spacer()
    }
    .safeAreaBar(edge: .bottom) {
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
            .padding(DesignConstants.Spacing.step2x)
    }
}

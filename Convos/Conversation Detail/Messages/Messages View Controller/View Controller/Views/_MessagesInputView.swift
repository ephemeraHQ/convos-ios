import PhotosUI
import SwiftUI

struct __MessagesInputView: View {
    @Binding var messageText: String
    @Binding var profileNameText: String
    @Binding var sendButtonEnabled: Bool
    @Binding var profile: Profile
    let onSend: () -> Void

    @State private var imageSelection: PhotosPickerItem?
    @State private var textEditorHeight: CGFloat = 0
    private let maxCapsuleHeight: CGFloat = 46.0

    var textClipShape: some Shape {
        if showingProfileNameEditor {
            AnyShape(RoundedRectangle(cornerRadius: 40.0))
        } else if textEditorHeight <= maxCapsuleHeight {
            AnyShape(Capsule())
        } else {
            AnyShape(RoundedRectangle(cornerRadius: maxCapsuleHeight / 2.0))
        }
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

    @Namespace private var profileEditorAnimation: Namespace.ID
    @State private var showingProfileNameEditor: Bool = false {
        didSet {
            withAnimation {
                if showingProfileNameEditor {
                    mode = .textField
                } else {
                    mode = .textView
                }
            }
        }
    }
    @State private var mode: DualTextView.Mode = .textView

    var body: some View {
        HStack(alignment: .bottom) {
            if showingProfileNameEditor {
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
                if showingProfileNameEditor {
                    PhotosPicker(
                        selection: $imageSelection,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 24.0))
                            .padding(.vertical, 7.5)
                            .padding(.horizontal, 14.0)
                            .foregroundColor(.white)
                    }
                    .frame(height: 52.0, alignment: .center)
                    .background(Circle().fill(.gray))
                    .matchedGeometryEffect(
                        id: "LeftView",
                        in: profileEditorAnimation
                    )
                    .padding([.leading, .vertical], DesignConstants.Spacing.step6x)
                } else {
                    Button {
                        withAnimation {
                            showingProfileNameEditor = true
                        }
                    } label: {
                        ProfileAvatarView(profile: profile)
                    }
                    .frame(height: sendButtonSize, alignment: .center)
                    .matchedGeometryEffect(
                        id: "LeftView",
                        in: profileEditorAnimation
                    )
                    .padding(.vertical, DesignConstants.Spacing.stepX)
                    .padding(.leading, DesignConstants.Spacing.stepX)
                    .frame(height: sendButtonSize, alignment: .bottomLeading)
                }

                Group {
                    DualTextViewRepresentable(
                        textViewText: $messageText,
                        textFieldText: $profileNameText,
                        mode: $mode,
                        height: $textEditorHeight,
                        textViewPlaceholder: "Chat as \(profileNameText)",
                        textFieldPlaceholder: "Somebody...",
                        font: .systemFont(ofSize: 16.0),
                        textColor: .colorTextPrimary
                    )
                    .frame(height: textEditorHeight)
                    .frame(maxWidth: .infinity, minHeight: 20.0, alignment: .center)
                    .padding(.horizontal, showingProfileNameEditor ? 20.0 : 0.0)
                    .padding(.vertical, showingProfileNameEditor ? DesignConstants.Spacing.step4x : 0.0)
                    .background(
                        RoundedRectangle(cornerRadius: DesignConstants.CornerRadius.mediumLarge)
                            .fill(showingProfileNameEditor ? .colorFillMinimal : .clear)
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                if showingProfileNameEditor {
                    Button {
                        withAnimation {
                            showingProfileNameEditor = false
                        }
                    } label: {
                        Image(systemName: "gear")
                            .foregroundStyle(.colorTextSecondary)
                            .font(.system(size: 24.0))
                            .padding(.vertical, 7.5)
                            .padding(.horizontal, 14.0)
                            .frame(height: 52.0, alignment: .center)
                            .background(.colorFillMinimal)
                            .mask(Circle())
                    }
                    .matchedGeometryEffect(
                        id: "RightView",
                        in: profileEditorAnimation
                    )
                    .padding([.trailing, .vertical], DesignConstants.Spacing.step6x)
                } else {
                    Button {
                        onSend()
                    } label: {
                        Image(systemName: "arrow.up")
                            .tint(.colorTextPrimary)
                            .font(.system(size: 16.0, weight: .medium))
                            .padding()
                            .frame(height: sendButtonSize, alignment: .center)
                            .background(.colorFillMinimal)
                            .mask(Circle())
                    }
                    .matchedGeometryEffect(
                        id: "RightView",
                        in: profileEditorAnimation
                    )
                    .frame(maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.vertical, DesignConstants.Spacing.stepX)
                    .disabled(!sendButtonEnabled)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(DesignConstants.Spacing.stepX)
            .glassEffect(.regular, in: textClipShape)
        }
        .padding(.horizontal, 10.0)
        .padding(.vertical, 6.0)
        .frame(maxWidth: .infinity)
        .background(.clear)
    }
}

#Preview {
    @Previewable @State var messageText: String = ""
    @Previewable @State var sendButtonEnabled: Bool = false
    @Previewable @State var profile: Profile = .mock()
    @Previewable @State var profileName: String = ""

    __MessagesInputView(
        messageText: $messageText,
        profileNameText: $profileName,
        sendButtonEnabled: $sendButtonEnabled,
        profile: $profile,
        onSend: {}
    )
}

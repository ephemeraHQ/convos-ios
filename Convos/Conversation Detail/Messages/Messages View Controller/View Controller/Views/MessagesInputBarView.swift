import SwiftUI

struct MessagesInputBarView: View {
    @Binding var text: String
    @Binding var sendButtonEnabled: Bool
    @Binding var profile: Profile
    @Binding var showingProfileNameEditor: Bool
    let profileEditorAnimationNamespace: Namespace.ID
    let textDidChange: (String) -> Void
    let onSend: () -> Void

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

    var body: some View {
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
                    showingProfileNameEditor = true
                } label: {
                    ProfileAvatarView(profile: profile)
                }
                .frame(width: sendButtonSize,
                       height: sendButtonSize)
                .padding(.vertical, DesignConstants.Spacing.stepX)
                .padding(.leading, DesignConstants.Spacing.stepX)
                .matchedGeometryEffect(
                    id: "button",
                    in: profileEditorAnimationNamespace
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

                    if text.isEmpty {
                        VStack {
                            HStack {
                                Text("Chat as \(profile.displayName)")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)

                                Spacer()
                            }

                            Spacer()
                        }
                    }
                }
                .frame(minHeight: maxCapsuleHeight)
                .padding(.horizontal, DesignConstants.Spacing.step3x)
                .fixedSize(horizontal: false, vertical: true)

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
                in: profileEditorAnimationNamespace
            )
        }
        .padding(.horizontal, 10.0)
        .padding(.vertical, 6.0)
        .frame(maxWidth: .infinity)
        .background(.clear)
    }
}

#Preview {
    @Previewable @State var text: String = ""
    @Previewable @State var sendButtonEnabled: Bool = false
    @Previewable @State var profile: Profile = .mock()
    @Previewable @State var showingProfileNameEditor: Bool = false
    @Previewable @Namespace var profileEditorAnimationNamespace: Namespace.ID
    VStack {
        Text("Hello!")
        Spacer()
    }.safeAreaInset(edge: .bottom) {
        MessagesInputBarView(
            text: $text,
            sendButtonEnabled: $sendButtonEnabled,
            profile: $profile,
            showingProfileNameEditor: $showingProfileNameEditor,
            profileEditorAnimationNamespace: profileEditorAnimationNamespace,
            textDidChange: { _ in },
            onSend: {}
        )
    }
}

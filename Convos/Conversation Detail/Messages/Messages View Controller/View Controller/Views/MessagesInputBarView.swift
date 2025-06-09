import SwiftUI

struct MessagesInputBarView: View {
    @State var text: String = ""
    @State private var textEditorHeight: CGFloat = 0
    @State var sendButtonEnabled: Bool = false
    private let maxCapsuleHeight: CGFloat = 38.0

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
        Group {
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
                .background(.colorFillMinimal)
                .mask(Circle())
                .padding(DesignConstants.Spacing.stepX)

                HStack(alignment: .bottom) {
                    TextEditor(text: $text)
                        .font(.body)
                        .foregroundStyle(.colorTextPrimary)
                        .lineLimit(5)
                        .textEditorStyle(.plain)
                        .tint(.colorTextPrimary)
                        .frame(minHeight: maxCapsuleHeight)
                        .padding(.horizontal, DesignConstants.Spacing.step3x)
                        .fixedSize(horizontal: false, vertical: true)
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
                    Button {
                    } label: {
                        Image(systemName: "arrow.up")
                            .foregroundStyle(sendButtonEnabled ? .colorTextPrimaryInverted : .colorTextSecondary)
                            .font(.caption.weight(.medium))
                            .frame(minWidth: sendButtonSize,
                                   minHeight: sendButtonSize)
                    }
                    .background(sendButtonEnabled ? .colorBackgroundInverted : .colorFillMinimal)
                    .mask(Circle())
                    .padding(.vertical, DesignConstants.Spacing.stepX)
                    .padding(.trailing, DesignConstants.Spacing.stepX)
                    .disabled(!sendButtonEnabled)
                }
                .clipShape(
                    textClipShape
                )
                .overlay(
                    textClipShape
                        .stroke(.colorBorderSubtle2, lineWidth: 1.0)
                )
                .padding(DesignConstants.Spacing.stepX)
            }
            .padding(.horizontal, 10.0)
            .padding(.vertical, 6.0)
        }
        .frame(maxWidth: .infinity)
        .background(.colorBackgroundPrimary)
    }
}

#Preview {
    VStack {
        Text("Hello!")
        Spacer()
    }.safeAreaInset(edge: .bottom) {
        MessagesInputBarView()
    }
}

import SwiftUI

struct MessageContainer<Content: View>: View {
    let style: MessagesCollectionCell.BubbleType
    let isOutgoing: Bool
    let cornerRadius: CGFloat = Constant.bubbleCornerRadius
    let content: () -> Content

    var spacer: some View {
        Group {
            Spacer()
            Spacer()
                .frame(maxWidth: 50.0)
        }
    }

    var mask: UnevenRoundedRectangle {
        switch style {
        case .normal:
            return .rect(
                topLeadingRadius: cornerRadius,
                bottomLeadingRadius: cornerRadius,
                bottomTrailingRadius: cornerRadius,
                topTrailingRadius: cornerRadius
            )
        case .tailed:
            if isOutgoing {
                return .rect(
                    topLeadingRadius: cornerRadius,
                    bottomLeadingRadius: cornerRadius,
                    bottomTrailingRadius: 2.0,
                    topTrailingRadius: cornerRadius
                )
            } else {
                return .rect(
                    topLeadingRadius: cornerRadius,
                    bottomLeadingRadius: 2.0,
                    bottomTrailingRadius: cornerRadius,
                    topTrailingRadius: cornerRadius
                )
            }
        }
    }

    var body: some View {
        HStack(spacing: 0.0) {
            if isOutgoing {
                spacer
            }

            content()
                .background(isOutgoing ? Color.black : Color(hue: 0.0, saturation: 0.0, brightness: 0.96))
                .foregroundColor(isOutgoing ? .white : .primary)
                .mask(mask)

            if !isOutgoing {
                spacer
            }
        }
    }
}

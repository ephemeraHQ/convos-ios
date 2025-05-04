import SwiftUI

struct MessageContainer<Content: View>: View {

    let style: Cell.BubbleType
    let isOutgoing: Bool
    let cornerRadius: CGFloat = Constants.bubbleCornerRadius
    let content: () -> Content

    // TODO: do this proportionally, not a fixed size
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
                        bottomTrailingRadius: 0.0,
                        topTrailingRadius: cornerRadius
                    )
                } else {
                    return .rect(
                        topLeadingRadius: cornerRadius,
                        bottomLeadingRadius: 0,
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
                .background(isOutgoing ? Color.black : Color.gray.opacity(0.2))
                .foregroundColor(isOutgoing ? .white : .primary)
                .mask(mask)

            if !isOutgoing {
                spacer
            }
        }
    }
}

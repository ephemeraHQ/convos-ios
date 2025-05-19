import SwiftUI

struct FlowLayout: Layout {
    var spacing: CGFloat = DesignConstants.Spacing.step2x

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? 0.0
        var width = 0.0
        var height: CGFloat = 0.0
        var rowHeight: CGFloat = 0.0

        for subview in subviews {
            let subviewSize = subview.sizeThatFits(
                ProposedViewSize(width: maxWidth, height: rowHeight)
            )

            if width + subviewSize.width > maxWidth {
                width = 0
                height += rowHeight + spacing
                rowHeight = 0
            }

            width += subviewSize.width + spacing
            rowHeight = max(rowHeight, subviewSize.height)
        }

        return CGSize(width: maxWidth, height: height + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let subviewSize = subview.sizeThatFits(
                ProposedViewSize(width: maxWidth, height: rowHeight)
            )

            if x + subviewSize.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }

            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(width: maxWidth, height: rowHeight)
            )

            x += subviewSize.width + spacing
            rowHeight = max(rowHeight, subviewSize.height)
        }
    }
}

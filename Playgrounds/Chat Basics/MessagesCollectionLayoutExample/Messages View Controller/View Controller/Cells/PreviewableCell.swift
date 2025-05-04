import UIKit

protocol PreviewableCell {
    /// Returns a view to be used as preview during hard press
    func previewView() -> UIView

    /// Returns the view that was used to render the preview
    /// used to hide the original source as we animate
    var previewSourceView: UIView { get }

    /// The frame of the preview content in the cell's coordinate space
    var previewContentFrame: CGRect { get }

    var actualPreviewSourceSize: CGSize { get }

    var horizontalInset: CGFloat { get }

    var sourceCellEdge: MessageReactionMenuController.Configuration.Edge { get }
}

typealias PreviewableCollectionViewCell = PreviewableCell & UICollectionViewCell

extension PreviewableCell where Self: UICollectionViewCell {
    var previewContentFrame: CGRect {
        contentView.bounds
    }

    var sourceCellEdge: MessageReactionMenuController.Configuration.Edge {
        // Default to .leading; override in conforming types if needed
        .leading
    }
}

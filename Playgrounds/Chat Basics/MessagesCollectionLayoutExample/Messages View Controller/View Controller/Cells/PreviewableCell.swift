import UIKit

protocol PreviewableCell {
    /// Returns a view to be used as preview during hard press
    func previewView() -> UIView?

    /// The frame of the preview content in the cell's coordinate space
    var previewContentFrame: CGRect { get }
}

extension PreviewableCell where Self: UICollectionViewCell {
    var previewContentFrame: CGRect {
        contentView.bounds
    }
}

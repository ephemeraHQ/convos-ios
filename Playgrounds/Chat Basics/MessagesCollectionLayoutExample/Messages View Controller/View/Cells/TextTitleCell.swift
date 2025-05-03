import UIKit
import SwiftUI

class TextTitleCell: UICollectionViewCell {
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .caption2)
        label.textColor = .gray
        label.textAlignment = .center
        return label
    }()

    private let verticalPadding: CGFloat = 16.0

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        contentView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: verticalPadding),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 0),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: 0),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -verticalPadding)
        ])
    }

    func setup(title: String) {
        titleLabel.text = title
    }

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let labelSize = titleLabel.sizeThatFits(CGSize(width: layoutAttributes.frame.width, height: .greatestFiniteMagnitude))

        let totalHeight = labelSize.height + (2 * verticalPadding)

        let targetSize = CGSize(width: layoutAttributes.frame.width, height: totalHeight)

        layoutAttributes.frame.size = contentView.systemLayoutSizeFitting(targetSize,
                                                                        withHorizontalFittingPriority: .required,
                                                                        verticalFittingPriority: .fittingSizeLevel)
        return layoutAttributes
    }
}

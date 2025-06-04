import SwiftUI
import UIKit

class TextTitleCell: UICollectionViewCell {
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        label.font = .preferredFont(forTextStyle: .caption2)
        label.textColor = .gray
        label.textAlignment = .center
        return label
    }()

    private let verticalPadding: CGFloat = 16.0
    private let horizontalPadding: CGFloat = 8.0

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
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: horizontalPadding),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -horizontalPadding),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -verticalPadding)
        ])
    }

    func setup(title: String) {
        titleLabel.text = title
        invalidateIntrinsicContentSize()
    }

    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutAttributes {
        let width = layoutAttributes.frame.width - (2 * horizontalPadding)
        let labelSize = titleLabel.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        )
        let totalHeight = labelSize.height + (2 * verticalPadding)
        layoutAttributes.frame.size.height = totalHeight
        return layoutAttributes
    }
}

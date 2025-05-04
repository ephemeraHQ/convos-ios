import UIKit
import SwiftUI

class TextTitleView: UICollectionReusableView {
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .caption2)
        label.textColor = .gray
        label.textAlignment = .center
        return label
    }()

    private let topPadding: CGFloat = 4.0

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: topPadding),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 0),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 0)
        ])
    }

    func setup(title: String) {
        titleLabel.text = title
    }

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let labelSize = titleLabel.sizeThatFits(CGSize(width: layoutAttributes.frame.width, height: .greatestFiniteMagnitude))

        let totalHeight = labelSize.height + topPadding

        let targetSize = CGSize(width: layoutAttributes.frame.width, height: totalHeight)

        layoutAttributes.frame.size = systemLayoutSizeFitting(targetSize,
                                                              withHorizontalFittingPriority: .required,
                                                              verticalFittingPriority: .fittingSizeLevel)
        return layoutAttributes
    }
}

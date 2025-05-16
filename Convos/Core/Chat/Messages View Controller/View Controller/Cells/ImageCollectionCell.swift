import SwiftUI
import UIKit

class ImageCollectionCell: UICollectionViewCell {
    private let containerView: UIView = UIView()
    private let imageView: UIImageView = UIImageView()
    private let loadingIndicator: UIActivityIndicatorView = UIActivityIndicatorView(style: .medium)
    private var imageAspectRatio: CGFloat = 1.0 // width / height
    private var currentImageURL: URL?
    private var imageLoadTask: Task<Void, Never>?
    private var messageType: Message.Source?
    private var leadingConstraint: NSLayoutConstraint?
    private var trailingConstraint: NSLayoutConstraint?
    private var dynamicConstraint: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        // Setup container view
        containerView.backgroundColor = .systemGray5
        containerView.layer.cornerRadius = Constant.bubbleCornerRadius
        containerView.layer.masksToBounds = true
        containerView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(containerView)

        // Setup loading indicator
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.hidesWhenStopped = true
        containerView.addSubview(loadingIndicator)
        loadingIndicator.startAnimating()

        // Setup image view
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        containerView.addSubview(imageView)

        leadingConstraint = containerView.leadingAnchor.constraint(
            equalTo: contentView.layoutMarginsGuide.leadingAnchor
        )
        trailingConstraint = containerView.trailingAnchor.constraint(
            equalTo: contentView.layoutMarginsGuide.trailingAnchor
        )

        NSLayoutConstraint.activate([
            // Container view constraints
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            containerView.widthAnchor.constraint(
                equalTo: contentView.widthAnchor,
                multiplier: Constant.maxWidth
            ),

            // Image view constraints
            imageView.topAnchor.constraint(equalTo: containerView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),

            // Loading indicator constraints
            loadingIndicator.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: containerView.centerYAnchor)
        ])
    }

    private func updateAlignment(for messageType: Message.Source) {
        // Deactivate all alignment constraints
        leadingConstraint?.isActive = false
        trailingConstraint?.isActive = false
        dynamicConstraint?.isActive = false

        switch messageType {
        case .incoming:
            leadingConstraint?.isActive = true
            dynamicConstraint = containerView.trailingAnchor.constraint(
                lessThanOrEqualTo: contentView.layoutMarginsGuide.trailingAnchor
            )
        case .outgoing:
            trailingConstraint?.isActive = true
            dynamicConstraint = containerView.leadingAnchor.constraint(
                greaterThanOrEqualTo: contentView.layoutMarginsGuide.leadingAnchor
            )
        }
        dynamicConstraint?.isActive = true
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        leadingConstraint?.isActive = false
        trailingConstraint?.isActive = false
        dynamicConstraint?.isActive = false
        imageView.alpha = 0
        imageView.image = nil
        imageAspectRatio = 1.0
        messageType = nil
        currentImageURL = nil
        imageLoadTask?.cancel()
        imageLoadTask = nil
        loadingIndicator.startAnimating()
    }

    // MARK: - Public Setup

    func setup(with source: ImageSource, messageType: Message.Source) {
        self.messageType = messageType
        updateAlignment(for: messageType)

        switch source {
        case .image(let uiImage):
            // Prepare for animation
            imageView.alpha = 0
            imageView.image = uiImage
            imageAspectRatio = uiImage.size.width / uiImage.size.height

            UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut) {
                self.imageView.alpha = 1
            } completion: { _ in
                self.loadingIndicator.stopAnimating()
            }

        case .imageURL(let url):
            currentImageURL = url
            imageView.alpha = 0
            imageView.image = nil
            loadingIndicator.startAnimating()
            imageLoadTask?.cancel()
            imageLoadTask = Task { [weak self] in
                await self?.loadRemoteImage(from: url)
            }
        }
    }

    private func loadRemoteImage(from url: URL) async {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else { return }
            // Check if the cell is still expecting this URL
            guard currentImageURL == url else { return }
            await MainActor.run {
                // Prepare for animation
                self.imageView.alpha = 0
                self.imageView.image = image
                self.imageAspectRatio = image.size.width / image.size.height
                invalidateIntrinsicContentSize()
                // Animate the image fade-in
                UIView.animate(
                    withDuration: 0.2,
                    delay: 0,
                    options: .curveEaseOut,
                    animations: {
                        self.imageView.alpha = 1
                    },
                    completion: { _ in
                        self.loadingIndicator.stopAnimating()
                    }
                )
            }
        } catch {
            await MainActor.run {
                self.loadingIndicator.stopAnimating()
            }
        }
    }

    // MARK: - Self Sizing

    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutAttributes {
        let maxWidth = contentView.bounds.width * Constant.maxWidth
        var width = layoutAttributes.size.width
        width = min(width, maxWidth)
        let height = width / imageAspectRatio
        layoutAttributes.size = CGSize(width: width, height: height)
        return layoutAttributes
    }
}

extension ImageCollectionCell: PreviewableCell {
    var sourceCellEdge: MessageReactionMenuController.Configuration.Edge {
        messageType == .incoming ? .leading : .trailing
    }
}

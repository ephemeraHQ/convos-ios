import UIKit

class CircularImageView: UIImageView {
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.masksToBounds = true
        layer.cornerRadius = bounds.height / 2
    }
}

class MessagesNavigationBar: UIView {
    enum Constant {
        static let contentHeight: CGFloat = 40.0
        static let regularHeight: CGFloat = 72.0
        static let compactHeight: CGFloat = 52.0
        static let contentViewVerticalPadding: CGFloat = 16.0
    }

    // MARK: - Properties

    private let blurView: UIVisualEffectView = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
    private let barView: UIView = UIView()
    private let contentView: UIView = UIView()
    let leftButton: UIButton = UIButton(type: .system)
    let rightButton: UIButton = UIButton(type: .system)
    private let stackView: UIStackView = {
        let stack: UIStackView = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .fill
        stack.spacing = 8.0
        return stack
    }()

    private let avatarImageView: CircularImageView = {
        let imageView: CircularImageView = CircularImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.backgroundColor = .systemGray5
        return imageView
    }()

    private let titleLabel: UILabel = {
        let label: UILabel = UILabel()
        label.font = .systemFont(ofSize: 16.0)
        label.textColor = .label
        return label
    }()

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Public Methods

    func configure(title: String, avatar: UIImage? = nil) {
        titleLabel.text = title
        avatarImageView.image = avatar
        avatarImageView.isHidden = avatar == nil
    }

    // MARK: - Private Methods

    private func setupUI() {
        backgroundColor = .white.withAlphaComponent(0.8)

        blurView.layer.borderWidth = 0
        blurView.layer.backgroundColor = UIColor.clear.cgColor
        blurView.layer.masksToBounds = false
        blurView.layer.shadowColor = UIColor.systemGray5.cgColor
        blurView.layer.shadowOffset = CGSize(width: 0, height: 1)
        blurView.layer.shadowOpacity = 1
        blurView.layer.shadowRadius = 0

        leftButton.tintColor = .black
        rightButton.tintColor = .black

        addSubview(blurView)
        blurView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        addSubview(barView)
        barView.translatesAutoresizingMaskIntoConstraints = false

        let barViewHeightConstraint = barView.heightAnchor.constraint(equalToConstant: 0.0)
        NSLayoutConstraint.activate([
            barView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            barView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            barView.bottomAnchor.constraint(equalTo: bottomAnchor),
            barViewHeightConstraint
        ])

        barView.addSubview(contentView)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: barView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: barView.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: barView.topAnchor, constant: Constant.contentViewVerticalPadding),
            contentView.bottomAnchor.constraint(
                equalTo: barView.bottomAnchor,
                constant: -Constant.contentViewVerticalPadding
            )
        ])

        contentView.addSubview(leftButton)
        leftButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leftButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            leftButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            leftButton.heightAnchor.constraint(equalTo: contentView.heightAnchor),
            leftButton.widthAnchor.constraint(equalTo: leftButton.heightAnchor)
        ])

        contentView.addSubview(rightButton)
        rightButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            rightButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            rightButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            rightButton.heightAnchor.constraint(equalTo: contentView.heightAnchor),
            rightButton.widthAnchor.constraint(equalTo: rightButton.heightAnchor)
        ])

        contentView.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leftButton.trailingAnchor, constant: 2),
            stackView.trailingAnchor.constraint(equalTo: rightButton.leadingAnchor, constant: -2),
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 0.0),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: 0.0)
        ])

        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(avatarImageView)
        NSLayoutConstraint.activate([
            avatarImageView.heightAnchor.constraint(equalTo: contentView.heightAnchor),
            avatarImageView.widthAnchor.constraint(equalTo: avatarImageView.heightAnchor)
        ])

        stackView.addArrangedSubview(titleLabel)

        registerForTraitChanges([
            UITraitVerticalSizeClass.self
        ]) { (self: MessagesNavigationBar, _: UITraitCollection) in
            self.updateNavigationBarHeight(barViewHeightConstraint)
        }

        updateNavigationBarHeight(barViewHeightConstraint)
    }

    private func updateNavigationBarHeight(_ constraint: NSLayoutConstraint) {
        let baseHeight = traitCollection.verticalSizeClass == .compact ?
            MessagesNavigationBar.Constant.compactHeight :
            MessagesNavigationBar.Constant.regularHeight
        constraint.constant = baseHeight
    }
}

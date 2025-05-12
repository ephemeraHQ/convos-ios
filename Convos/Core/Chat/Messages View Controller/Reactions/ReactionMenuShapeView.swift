import UIKit

// swiftlint:disable force_cast

class ReactionMenuShapeView: UIView {
    // MARK: - Properties

    var fillColor: UIColor = .systemBackground {
        didSet {
            shapeLayer.fillColor = fillColor.cgColor
        }
    }

    override class var layerClass: AnyClass {
        return CAShapeLayer.self
    }

    var shapeLayer: CAShapeLayer {
        return layer as! CAShapeLayer
    }

    // MARK: - Initialization

    override func layoutSubviews() {
        super.layoutSubviews()

        if bounds.width == bounds.height {
            // Create circle path
            shapeLayer.path = UIBezierPath(roundedRect: bounds, cornerRadius: bounds.height / 2.0).cgPath
        } else {
            // Create rounded rectangle path
            shapeLayer.path = UIBezierPath(roundedRect: bounds, cornerRadius: Constant.cornerRadius).cgPath
        }
    }

    // MARK: - Shadow Configuration

    func configureShadow(opacity: Float = 0.15, radius: CGFloat = 10.0, offset: CGSize = .zero) {
        layer.shadowOpacity = opacity
        layer.shadowRadius = radius
        layer.shadowOffset = offset
    }

    // MARK: - Animation

    func animateToShape(frame targetFrame: CGRect,
                        alpha: CGFloat,
                        color: UIColor? = nil,
                        completion: (() -> Void)? = nil) {
        UIView.animate(
            withDuration: 0.5,
            delay: 0,
            usingSpringWithDamping: 0.8,
            initialSpringVelocity: 0.0,
            options: [.curveEaseInOut, .layoutSubviews, .beginFromCurrentState],
            animations: {
                self.frame = targetFrame
                self.alpha = alpha
                if let color = color {
                    self.fillColor = color
                }
            },
            completion: { _ in
                completion?()
            }
        )
    }
    private enum Constant {
        static let cornerRadius: CGFloat = 24.0
    }
}

// MARK: - Animation Delegate Helper

private class AnimationDelegate: NSObject, CAAnimationDelegate {
    private let completion: () -> Void

    init(_ completion: @escaping () -> Void) {
        self.completion = completion
        super.init()
    }

    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        completion()
    }
}

// swiftlint:enable force_cast

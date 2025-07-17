import SwiftUI
import UIKit

final class InputHostingController<Content: View>: UIView {
    private let hostingController: UIHostingController<Content>

    init(rootView: Content) {
        self.hostingController = UIHostingController<Content>(rootView: rootView)
        super.init(frame: .zero)
        addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.backgroundColor = .clear
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        KeyboardListener.shared.add(delegate: self)
    }

    deinit {
        KeyboardListener.shared.remove(delegate: self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        hostingController.view.intrinsicContentSize
    }

    override var canBecomeFirstResponder: Bool {
        true
    }
}

extension InputHostingController: KeyboardListenerDelegate {
    func keyboardWillShow(info: KeyboardInfo) {
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    func keyboardWillHide(info: KeyboardInfo) {
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    func keyboardWillChangeFrame(info: KeyboardInfo) {
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    func keyboardDidChangeFrame(info: KeyboardInfo) {
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }
}

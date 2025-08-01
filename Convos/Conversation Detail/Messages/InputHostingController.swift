import SwiftUI
import UIKit

final class InputHostingController<Content: View>: UIView {
    private let hostingController: UIHostingController<Content>

    init(rootView: Content) {
        self.hostingController = UIHostingController<Content>(rootView: rootView)
        self.hostingController.sizingOptions = .intrinsicContentSize
        super.init(frame: .zero)
        addSubview(hostingController.view)
        autoresizingMask = [.flexibleHeight]
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.backgroundColor = .clear
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),
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
        let size = hostingController.view.intrinsicContentSize
        return .init(width: size.width, height: size.height + DesignConstants.Spacing.step2x)
    }
}

extension InputHostingController: KeyboardListenerDelegate {
    func keyboardWillShow(info: KeyboardInfo) {
//        invalidateIntrinsicContentSize()
    }

    func keyboardWillHide(info: KeyboardInfo) {
//        invalidateIntrinsicContentSize()
    }

    func keyboardWillChangeFrame(info: KeyboardInfo) {
        invalidateIntrinsicContentSize()
    }

    func keyboardDidChangeFrame(info: KeyboardInfo) {
        invalidateIntrinsicContentSize()
    }
}

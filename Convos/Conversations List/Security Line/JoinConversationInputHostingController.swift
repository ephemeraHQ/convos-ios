import SwiftUI
import UIKit

final class JoinConversationInputHostingController: UIView {
    private let hostingController: UIHostingController<JoinConversationInputView>

    init(viewModel: JoinConversationInputViewModelType) {
        self.hostingController = UIHostingController<JoinConversationInputView>(rootView: .init(viewModel: viewModel))
        super.init(frame: .zero)
        addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
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

extension JoinConversationInputHostingController: KeyboardListenerDelegate {
    func keyboardWillShow(info: KeyboardInfo) {
        invalidateIntrinsicContentSize()
    }

    func keyboardWillHide(info: KeyboardInfo) {
        invalidateIntrinsicContentSize()
    }

    func keyboardWillChangeFrame(info: KeyboardInfo) {
        invalidateIntrinsicContentSize()
    }
}

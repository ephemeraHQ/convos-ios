import SwiftUI
import UIKit

class MessagesToolbarViewHost: UIView {
    private var hostingController: UIHostingController<MessagesToolbarView>
    private var conversationState: ConversationState
    private var emptyConversationTitle: String

    // MARK: - Initialization

    init(conversationState: ConversationState,
         emptyConversationTitle: String = "New chat",
         dismissAction: DismissAction) {
        self.conversationState = conversationState
        self.emptyConversationTitle = emptyConversationTitle
        let swiftUIView = MessagesToolbarView(
            conversationState: conversationState,
            emptyConversationTitle: emptyConversationTitle,
            dismissAction: dismissAction
        )

        let hostingController = UIHostingController(rootView: swiftUIView)
        hostingController.view.backgroundColor = .clear
        self.hostingController = hostingController
        super.init(frame: .zero)
        updateHostingController()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Private Methods

    private func updateHostingController() {
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }
}

import SwiftUI
import UIKit

/// A UIView that can host any SwiftUI View for use in UIKit hierarchies.
class SwiftUIViewWrapper<Content: View>: UIView {
    private let hostingController: UIHostingController<Content>

    /// Initialize with a SwiftUI view builder.
    init(@ViewBuilder content: () -> Content) {
        self.hostingController = UIHostingController(rootView: content())
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.backgroundColor = .clear
        addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    /// Update the SwiftUI view.
    func update(_ content: Content) {
        hostingController.rootView = content
    }
}

import SwiftUI
import UIKit

// Example usage:
/*
 let chatListViewController = ChatListView().asViewController()
 // or
 let chatListViewController = SwiftUIHostingController(rootView: ChatListView())
 */

/// A utility wrapper that converts SwiftUI views to UIViewController
struct SwiftUIViewController<Content: View>: UIViewControllerRepresentable {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    func makeUIViewController(context: Context) -> UIHostingController<Content> {
        UIHostingController(rootView: content())
    }

    func updateUIViewController(_ uiViewController: UIHostingController<Content>, context: Context) {
        uiViewController.rootView = content()
    }
}

/// A utility wrapper that converts SwiftUI views to UIViewController
class SwiftUIHostingController<Content: View>: UIHostingController<Content> {
    override func viewDidLoad() {
        super.viewDidLoad()
        setupNavigationBar()
    }

    private func setupNavigationBar() {
        // Hide the navigation bar to prevent double navigation bars
        navigationController?.setNavigationBarHidden(true, animated: false)
    }
}

/// Extension to easily create a UIViewController from a SwiftUI view
extension View {
    /// Wraps the SwiftUI view in a UIViewController
    func asViewController() -> UIViewController {
        SwiftUIHostingController(rootView: self)
    }
}

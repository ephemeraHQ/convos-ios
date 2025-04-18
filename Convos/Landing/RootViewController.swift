import AnchorKit
import SwiftUI
import UIKit

final class RootViewController: UIViewController {
    let authService: AuthService = .init()

    override func viewDidLoad() {
        super.viewDidLoad()
        let rootView = RootView(authService: authService)
        let hostingController = UIHostingController(rootView: rootView)
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.constrainEdges(to: view)
        hostingController.didMove(toParent: self)
    }
}

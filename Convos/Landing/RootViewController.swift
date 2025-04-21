import AnchorKit
import SwiftUI
import UIKit

final class RootViewController: UIViewController {
    let authService: AuthServiceProtocol = MockAuthService()
    let analyticsService: AnalyticsServiceProtocol = PosthogAnalyticsService.shared

    override func viewDidLoad() {
        super.viewDidLoad()

        let rootView = RootView(authService: authService,
                                analyticsService: analyticsService)
        let hostingController = UIHostingController(rootView: rootView)
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.constrainEdges(to: view)
        hostingController.didMove(toParent: self)
    }
}

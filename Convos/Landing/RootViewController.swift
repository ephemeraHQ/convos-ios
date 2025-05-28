import AnchorKit
import SwiftUI
import UIKit

final class RootViewController: UIViewController {
    let convos: ConvosClient = .client(environment: .dev)
    let analyticsService: AnalyticsServiceProtocol = PosthogAnalyticsService.shared

    override func viewDidLoad() {
        super.viewDidLoad()

        let rootView = RootView(convos: convos,
                                analyticsService: analyticsService)
        let hostingController = UIHostingController(rootView: rootView)
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.constrainEdges(to: view)
        hostingController.didMove(toParent: self)
    }
}

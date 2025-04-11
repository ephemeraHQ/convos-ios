//
//  LandingViewController.swift
//  Convos
//
//  Created by Joe on 4/11/25.
//

import AnchorKit
import SwiftUI
import UIKit

final class LandingViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let landingView = LandingView()
        let hostingController = UIHostingController(rootView: landingView)
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.constrainEdges(to: view)
        hostingController.didMove(toParent: self)
    }
}


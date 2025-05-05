import Foundation
import UIKit

extension UIView {
    func superview<T>(of type: T.Type) -> T? {
        superview as? T ?? superview.flatMap { $0.superview(of: type) }
    }

    func subview<T>(of type: T.Type) -> T? {
        subviews.compactMap { $0 as? T ?? $0.subview(of: type) }.first
    }

}

extension UIViewController {
    func topMostViewController() -> UIViewController {
        guard let presentedViewController else { return self }

        if let navigationViewController = presentedViewController as? UINavigationController {
            if let visibleViewController = navigationViewController.visibleViewController {
                return visibleViewController.topMostViewController()
            } else {
                return navigationViewController
            }
        }

        if let tabBarViewController = presentedViewController as? UITabBarController {
            if let selectedViewController = tabBarViewController.selectedViewController {
                return selectedViewController.topMostViewController()
            }

            return tabBarViewController
        }

        return presentedViewController.topMostViewController()
    }
}

extension UIApplication {
    func topMostViewController() -> UIViewController? {
        UIApplication.shared
            .connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first?
            .rootViewController?
            .topMostViewController()
    }
}

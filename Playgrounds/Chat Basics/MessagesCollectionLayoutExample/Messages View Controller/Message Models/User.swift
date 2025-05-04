import DifferenceKit
import Foundation
import UIKit

struct User: Hashable {
    let id: Int
    let name: String
}

extension User: Differentiable {}

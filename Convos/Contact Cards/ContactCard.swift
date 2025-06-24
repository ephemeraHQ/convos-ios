import Foundation
import SwiftUI

extension ContactCard {
    static func mock(type: ContactCardType = .standard(.mock())) -> Self {
        .init(type: type)
    }
}

enum ContactCardType: Hashable {
    case standard(Inbox),
         ephemeral([Inbox]),
         cash([Inbox])
}

struct ContactCard: Hashable {
    let type: ContactCardType
}

extension ContactCard {
    var color: Color {
        switch type {
        case .standard:
            return .colorStandard
        case .cash:
            return .colorCash
        case .ephemeral:
            return .colorOrange
        }
    }

    var iconImage: Image {
        switch type {
        case .standard, .ephemeral:
            return Image("convosIconRounded")
        case .cash:
            return Image("cashIconRounded")
        }
    }
}

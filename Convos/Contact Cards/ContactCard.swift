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

struct ContactCard: Identifiable, Hashable {
    var id: String {
        switch type {
        case .standard(let inbox):
            return inbox.id
        case let .ephemeral(inboxes),
            let .cash(inboxes):
            return "\(inboxes.hashValue)"
        }
    }

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

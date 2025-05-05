import DifferenceKit
import Foundation
import UIKit

enum MessageType: Hashable {
    case incoming, outgoing

    var isIncoming: Bool {
        self == .incoming
    }
}

enum MessageStatus: Hashable {
    case sent, delivered, read
}

extension Cell.Alignment {
    var isIncoming: Bool {
        self == .leading
    }
}

struct DateGroup: Hashable {
    var id: UUID
    var date: Date
    var value: String {
        MessagesDateFormatter.shared.string(from: date)
    }

    init(id: UUID, date: Date) {
        self.id = id
        self.date = date
    }
}

extension DateGroup: Differentiable {
    var differenceIdentifier: Int {
        hashValue
    }

    func isContentEqual(to source: DateGroup) -> Bool {
        self == source
    }
}

struct MessageGroup: Hashable {
    var id: UUID
    var title: String
    var type: MessageType
}

extension MessageGroup: Differentiable {
    var differenceIdentifier: Int {
        hashValue
    }

    func isContentEqual(to source: MessageGroup) -> Bool {
        self == source
    }
}

enum ImageSource: Hashable {
    case image(UIImage)
    case imageURL(URL)
    var isLocal: Bool {
        switch self {
        case .image: return true
        case .imageURL: return false
        }
    }
}

struct Message: Hashable {
    enum Data: Hashable {
        case text(String)
        case image(ImageSource, isLocallyStored: Bool)
    }

    var id: UUID
    var date: Date
    var data: Data
    var owner: User
    var type: MessageType
    var status: MessageStatus = .sent
}

extension Message: Differentiable {
    var differenceIdentifier: Int {
        id.hashValue
    }

    func isContentEqual(to source: Message) -> Bool {
        self == source
    }
}

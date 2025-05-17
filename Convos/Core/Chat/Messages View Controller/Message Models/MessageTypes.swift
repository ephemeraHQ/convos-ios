import DifferenceKit
import Foundation
import UIKit

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
    var source: MessageSource
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

extension Message: Differentiable {
    var differenceIdentifier: Int {
        id.hashValue
    }

    func isContentEqual(to source: Message) -> Bool {
        self == source
    }
}

import DifferenceKit
import Foundation

struct MessagesCollectionSection: Hashable {
    var id: Int
    var title: String
    var cells: [MessagesCollectionCell]
}

extension MessagesCollectionSection: DifferentiableSection {
    var differenceIdentifier: Int {
        id
    }

    func isContentEqual(to source: MessagesCollectionSection) -> Bool {
        id == source.id
    }

    var elements: [MessagesCollectionCell] {
        cells
    }

    init<C: Swift.Collection>(
        source: MessagesCollectionSection,
        elements: C) where C.Element == MessagesCollectionCell {
        self.init(id: source.id, title: source.title, cells: Array(elements))
    }
}

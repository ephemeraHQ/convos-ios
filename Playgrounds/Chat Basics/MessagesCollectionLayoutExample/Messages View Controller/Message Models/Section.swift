import DifferenceKit
import Foundation

struct Section: Hashable {
    var id: Int
    var title: String
    var cells: [Cell]
}

extension Section: DifferentiableSection {
    var differenceIdentifier: Int {
        id
    }

    func isContentEqual(to source: Section) -> Bool {
        id == source.id
    }

    var elements: [Cell] {
        cells
    }

    init<C: Swift.Collection>(source: Section, elements: C) where C.Element == Cell {
        self.init(id: source.id, title: source.title, cells: Array(elements))
    }
}

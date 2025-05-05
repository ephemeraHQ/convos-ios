import Foundation
import UIKit

struct RawMessage: Hashable {
    enum Data: Hashable {
        case text(String)
        case image(ImageSource)
    }

    var id: UUID
    var date: Date
    var data: Data
    var userId: Int
    var status: MessageStatus = .sent
}

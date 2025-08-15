import Foundation
import GRDB
import XMTPiOS

extension XMTPiOS.MessageDeliveryStatus {
    var status: MessageStatus {
        switch self {
        case .failed: return .failed
        case .unpublished: return .unpublished
        case .published: return .published
        case .all: return .unknown
        }
    }
}

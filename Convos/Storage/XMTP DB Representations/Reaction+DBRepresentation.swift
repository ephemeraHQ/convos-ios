import Foundation
import GRDB
import XMTPiOS

extension XMTPiOS.Reaction {
    var emoji: String {
        switch schema {
        case .unicode:
            if let scalarValue = UInt32(content.replacingOccurrences(of: "U+", with: ""), radix: 16),
               let scalar = UnicodeScalar(scalarValue) {
                return String(scalar)
            }
        default:
            break
        }
        return content
    }
}

import Foundation

extension Date {
    /// Returns a short relative string like "1h", "12h", "1w", etc.
    public func relativeShort(to referenceDate: Date = .init()) -> String {
        let seconds = Int(referenceDate.timeIntervalSince(self))
        let minute = 60
        let hour   = 60 * minute
        let day    = 24 * hour
        let week   = 7 * day

        switch seconds {
        case 0..<30:
            return "now"
        case 30..<minute:
            return "\(seconds)s"
        case minute..<hour:
            return "\(seconds / minute)m"
        case hour..<day:
            return "\(seconds / hour)h"
        case day..<week:
            return "\(seconds / day)d"
        default:
            return "\(seconds / week)w"
        }
    }

    public var nanosecondsSince1970: Int64 {
        Int64(timeIntervalSince1970 * 1_000_000_000)
    }
}

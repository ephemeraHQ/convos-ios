import Foundation

extension Data {
    struct HexEncodingOptions: OptionSet {
        let rawValue: Int
        static let upperCase: HexEncodingOptions = .init(rawValue: 1 << 0)
    }

    func hexEncodedString(options: HexEncodingOptions = []) -> String {
        let format = options.contains(.upperCase) ? "%02hhX" : "%02hhx"
        return self.map { String(format: format, $0) }.joined()
    }

    var toHex: String {
        return reduce("") { $0 + String(format: "%02x", $1) }
    }

    init?(hexString: String) {
        var hex = hexString
        if hex.hasPrefix("0x") {
            hex = String(hex.dropFirst(2))
        }

        guard hex.count.isMultiple(of: 2) else { return nil }

        var newData = Data()
        var index = hex.startIndex

        for _ in 0..<(hex.count / 2) {
            let nextIndex = hex.index(index, offsetBy: 2)
            if let b = UInt8(hex[index..<nextIndex], radix: 16) {
                newData.append(b)
            } else {
                return nil
            }
            index = nextIndex
        }

        self = newData
    }
}

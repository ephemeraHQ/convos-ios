import Foundation

extension String {
    /// Checks if the string is a valid Ethereum address format (0x + 40 hex chars)
    var isValidEthereumAddressFormat: Bool {
        let pattern = "^0x[a-fA-F0-9]{40}$"
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: self.utf16.count)
        return regex?.firstMatch(in: self, options: [], range: range) != nil
    }
}

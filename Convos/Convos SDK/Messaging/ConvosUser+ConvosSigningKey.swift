import Foundation

extension ConvosSDK.User {
    var signingKey: ConvosSigningKey {
        get throws {
            guard let publicIdentifier = walletAddress else {
                throw ConvosSigningKeyError.missingPublicIdentifier
            }
            return ConvosSigningKey(publicIdentifier: publicIdentifier, chainId: chainId) { message in
                guard let data = try await self.sign(message: message) else {
                    throw ConvosSigningKeyError.nilDataWhenSigningMessage
                }
                return .init(rawData: data)
            }
        }
    }
}

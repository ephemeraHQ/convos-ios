import Foundation

extension ConvosSDK.User {
    var signingKey: ConvosSigningKey {
        get throws {
            guard let publicIdentifier = publicIdentifier else {
                throw ConvosSigningKeyError.missingPublicIdentifier
            }
            guard let chainId = chainId else {
                throw ConvosSigningKeyError.missingChainId
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

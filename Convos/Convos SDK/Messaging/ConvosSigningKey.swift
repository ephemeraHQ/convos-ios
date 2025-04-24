import Foundation
import XMTPiOS

struct ConvosSigningKey: SigningKey {
    typealias Signer = (String) async throws -> XMTPiOS.SignedData

    let publicIdentifier: String
    let chainId: Int64?
    let signer: Signer

    var identity: XMTPiOS.PublicIdentity {
        .init(kind: .ethereum, identifier: publicIdentifier)
    }

    var type: SignerType {
        .SCW
    }

    func sign(_ message: String) async throws -> XMTPiOS.SignedData {
        return try await signer(message)
    }
}

enum ConvosSigningKeyError: Error {
    case missingPublicIdentifier, missingChainId, nilDataWhenSigningMessage
}

import CryptoKit
import Foundation
import XMTPiOS

struct SecureEnclaveSigningKey: SigningKey {
    var identity: XMTPiOS.PublicIdentity
    
    let privateKey: SecureEnclave.P256.Signing.PrivateKey

    func sign(_ message: String) async throws -> XMTPiOS.SignedData {
        let data = Data(message.utf8)
        let signature = try privateKey.signature(for: data)
        return SignedData(rawData: signature.rawRepresentation)
    }

    var publicKeyData: Data {
        privateKey.publicKey.rawRepresentation
    }
}

import CryptoKit
import Foundation
import LocalAuthentication
import PasskeyAuth
import XMTPiOS

extension Data {
    init?(base64URLEncoded input: String) {
        var base64 = input
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        self.init(base64Encoded: base64)
    }
}

final class PasskeySigningKey: SigningKey {
    enum PasskeySigningKeyError: Error {
        case signingFailed(String),
             failedEncoding(String)
    }

	let credentialID: Data
    let publicKey: Data
	let identity: PublicIdentity
    private let passkeyAuth: PasskeyAuth

    init(credentialID: Data, publicKey: Data, passkeyAuth: PasskeyAuth) {
        self.credentialID = credentialID
        self.publicKey = publicKey
        let fingerprint = Data(SHA256.hash(data: publicKey)).toHex
		self.identity = PublicIdentity(
            kind: .passkey,
            identifier: fingerprint
        )
        self.passkeyAuth = passkeyAuth
	}

	var type: SignerType { .EOA }

    func base64URLEncoded(_ string: String) throws -> String {
        guard let raw = string.data(using: .utf8) else {
            throw PasskeySigningKeyError.failedEncoding(
                "Could not encode challenge string as UTF-8"
            )
        }
        return raw.base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
    }

    func sign(_ message: String) async throws -> SignedData {
        let base64urlEncodedMessage = try base64URLEncoded(message)

        guard let challengeData = base64urlEncodedMessage.data(using: .utf8) else {
            throw PasskeySigningKeyError.signingFailed("Could not encode challenge string as UTF-8")
        }

        let assertion = try await passkeyAuth.sign(challenge: challengeData)

        let hash = SHA256.hash(data: assertion.rawClientDataJSON)
        let verificationData = assertion.rawAuthenticatorData + Data(hash)
        let sec1Key = try P256.Signing.PublicKey(x963Representation: publicKey)
        let signature = try P256.Signing.ECDSASignature(derRepresentation: assertion.signature)
        let isValid = sec1Key.isValidSignature(signature, for: verificationData)
        Log.info("Internal signing validation check returned `isValid`: \(isValid)")

        return SignedData(
            rawData: assertion.signature,
            publicKey: publicKey,
            authenticatorData: assertion.rawAuthenticatorData,
            clientDataJson: assertion.rawClientDataJSON
        )
    }
}

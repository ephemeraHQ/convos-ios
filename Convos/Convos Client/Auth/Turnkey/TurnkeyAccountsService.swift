import AuthenticationServices
import CryptoKit
import Foundation
import TurnkeyCrypto
import TurnkeyHttp
import TurnkeyPasskeys
import TurnkeySwift

enum TurnkeyAccountsServiceError: Error {
    case invalidTurnkeyContext,
         walletMissing,
         failedCreatingSubOrg,
         failedCreatingWallet,
         failedCreatingAccount,
         failedGettingAccounts,
         failedFindingPasskeyPresentationAnchor
}

class TurnkeyAccountsService: AuthAccountsServiceProtocol {
    private let turnkey: TurnkeyContext
    private let environment: AppEnvironment

    init(turnkey: TurnkeyContext, environment: AppEnvironment) {
        self.turnkey = turnkey
        self.environment = environment
    }

    @MainActor
    func presentationAnchor() throws -> ASPresentationAnchor {
        do {
            return try TurnkeyPresentationAnchorProvider.presentationAnchor()
        } catch TurnkeyPresentationAnchorError.failedFindingPasskeyPresentationAnchor {
            throw TurnkeyAccountsServiceError.failedFindingPasskeyPresentationAnchor
        }
    }

    func addAccount(displayName: String) async throws -> any AuthServiceRegisteredResultType {
        guard let client = turnkey.client else {
            throw TurnkeyAccountsServiceError.invalidTurnkeyContext
        }

        guard let organizationId = turnkey.user?.organizationId else {
            throw TurnkeyAccountsServiceError.invalidTurnkeyContext
        }

//        let presentationAnchor = try await presentationAnchor()
//
//        let random = SymmetricKey(size: .bits256)
//        let challenge = Data(random.withUnsafeBytes { Data($0) })
//        let challengeString = challenge.base64EncodedString()
//        let stamper = PasskeyStamper(
//            rpId: environment.relyingPartyIdentifier,
//            presentationAnchor: presentationAnchor
//        )
//        let result = try await stamper.assert(challenge: challenge)
//        let (_, publicKeyCompressed, _) = TurnkeyCrypto.generateP256KeyPair()
//
//        let subOrgResponse = try await client.createSubOrganization(
//            organizationId: Secrets.TURNKEY_PUBLIC_ORGANIZATION_ID,
//            subOrganizationName: "OTR Organization",
//            rootUsers: [
//                .init(
//                    userName: "Default User",
//                    apiKeys: [
//                        .init(
//                            apiKeyName: "Temporary API key",
//                            publicKey: publicKeyCompressed,
//                            curveType: .API_KEY_CURVE_P256,
//                            expirationSeconds: "900"
//                        )
//                    ],
//                    authenticators: [
//                        .init(
//                            authenticatorName: "Passkey",
//                            challenge: challengeString,
//                            attestation: .init(
//                                credentialId: result.credentialId,
//                                clientDataJson: result.clientDataJSON,
//                                attestationObject: result.authenticatorData.base64URLEncodedString(),
//                                transports: [.AUTHENTICATOR_TRANSPORT_INTERNAL]
//                            )
//                        )
//                    ],
//                    oauthProviders: []
//                )
//            ],
//            rootQuorumThreshold: 1,
//            wallet: .init(
//                walletName: "Wallet",
//                accounts: [
//                    .init(
//                        curve: .CURVE_SECP256K1,
//                        pathFormat: .PATH_FORMAT_BIP32,
//                        path: Constant.defaultEthereumPath,
//                        addressFormat: .ADDRESS_FORMAT_ETHEREUM
//                    )
//                ]
//            ),
//            disableEmailRecovery: nil,
//            disableEmailAuth: nil,
//            disableSmsAuth: nil,
//            disableOtpEmailAuth: nil
//        )
//
//        Logger.info("Create sub org response: \(subOrgResponse)")
//        guard
//            case let .json(body) = subOrgResponse.body,
//            let subOrgResult = body.activity.result.createSubOrganizationResult else {
//            throw TurnkeyAccountsServiceError.failedCreatingSubOrg
//        }
//
//        Logger.info("Created sub org: \(subOrgResult.subOrganizationId) users: \(subOrgResult.rootUserIds ?? [])")

        let otrWalletId: String
        let otrWalletAddress: String
        if turnkey.user?.otrWallet == nil {
            let response = try await client.createWallet(
                organizationId: organizationId,
                walletName: TurnkeyAuthService.Constant.otrWalletName,
                accounts: [
                    .init(
                        curve: .CURVE_SECP256K1,
                        pathFormat: .PATH_FORMAT_BIP32,
                        path: Constant.defaultEthereumPath,
                        addressFormat: .ADDRESS_FORMAT_ETHEREUM
                    )
                ],
                mnemonicLength: nil
            )

            Logger.info("Added wallet: \(response)")
            guard
                case let .json(body) = response.body,
                let walletResult = body.activity.result.createWalletResult,
                walletResult.addresses.count == 1,
                let address = walletResult.addresses.first
            else {
                throw TurnkeyAccountsServiceError.failedCreatingWallet
            }

            otrWalletId = walletResult.walletId
            otrWalletAddress = address
        } else if let otrWallet = turnkey.user?.otrWallet {
            otrWalletId = otrWallet.id
            let accountResponse = try await client.createWalletAccounts(
                organizationId: organizationId,
                walletId: otrWalletId,
                accounts: [
                    .init(
                        curve: .CURVE_SECP256K1,
                        pathFormat: .PATH_FORMAT_BIP32,
                        path: Constant.defaultEthereumPath,
                        addressFormat: .ADDRESS_FORMAT_ETHEREUM
                    )
                ]
            )

            guard
                case let .json(body) = accountResponse.body,
                let accountResult = body.activity.result.createWalletAccountsResult,
                accountResult.addresses.count == 1,
                let address = accountResult.addresses.first
            else {
                throw TurnkeyAccountsServiceError.failedCreatingAccount
            }
            otrWalletAddress = address
        } else {
            throw TurnkeyAccountsServiceError.failedCreatingWallet
        }

        await turnkey.refreshUser()

        guard let accounts = turnkey.user?.otrWallet?.accounts else {
            throw TurnkeyAccountsServiceError.failedGettingAccounts
        }

        guard let account = accounts.first(where: { $0.address == otrWalletAddress }) else {
            throw TurnkeyAccountsServiceError.failedCreatingAccount
        }

        return AuthServiceRegisteredResult(
            displayName: displayName,
            inbox: AuthServiceInbox(
                type: .ephemeral,
                provider: .external(.turnkey),
                providerId: account.id,
                signingKey: account,
                databaseKey: try account.databaseKey
            )
        )
    }

    internal enum Constant {
        static var defaultEthereumPath: String = "m/44'/60'/0'/0/0"
    }
}

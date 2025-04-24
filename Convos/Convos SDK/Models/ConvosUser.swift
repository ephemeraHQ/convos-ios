import Foundation
import PrivySDK

struct ConvosUser: ConvosSDK.User {
    fileprivate let privyUser: PrivyUser
    var id: String { privyUser.id }

    init(privyUser: PrivyUser) {
        self.privyUser = privyUser
    }

    var chainId: Int64? {
        guard let wallet = privyUser.embeddedEthereumWallets.first else {
            Logger.info("No wallet found, returning nil chainId")
            return nil
        }
        Logger.info("Returning chainId \(wallet.provider.chainId) as Int64: \(Int64(wallet.provider.chainId))")
        return Int64(wallet.provider.chainId)
    }

    var publicIdentifier: String? {
        privyUser.embeddedEthereumWallets.first?.address
    }
}

extension ConvosUser {
    func sign(message: String) async throws -> Data? {
        guard let wallet = privyUser.embeddedEthereumWallets.first else {
            Logger.warning("Missing wallet, skipping sign for message")
            return nil
        }
        Logger.info("Requesting personal sign from provider with chain id: \(wallet.provider.chainId)")
        do {
            let request = EthereumRpcRequest(method: "personal_sign",
                                             params: [
                                                message,
                                                wallet.address
                                             ])
            Logger.info("Making Ethereum RPC Request: \(request)")
            let result = try await wallet.provider.request(request)
            Logger.info("Received personal sign result from Privy: \(result)")
            let hexData = Data(hexString: result)
            Logger.info("Converted personal sign result to Data for XMTP: \(String(describing: hexData))")
            return hexData
        } catch {
            Logger.error("Error making sign request to Privy: \(error)")
        }
        return nil
    }
}

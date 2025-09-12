import Foundation

actor MockSyncingManager: SyncingManagerProtocol {
    func start(with client: AnyClientProvider, apiClient: any ConvosAPIClientProtocol) {
    }

    func stop() {
    }
}

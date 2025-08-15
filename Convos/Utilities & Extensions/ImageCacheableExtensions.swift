import ConvosCore

extension Profile: ImageCacheable {
    // MARK: - ImageCacheable
    var imageCacheIdentifier: String {
        inboxId
    }
}

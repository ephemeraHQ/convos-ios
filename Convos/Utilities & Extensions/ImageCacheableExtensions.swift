import ConvosCore

extension Profile: ImageCacheable {
    var imageCacheIdentifier: String {
        inboxId
    }
}

extension Conversation: ImageCacheable {
    var imageCacheIdentifier: String {
        id
    }
}

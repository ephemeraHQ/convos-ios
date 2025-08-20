import Foundation

extension Profile: ImageCacheable {
    public var imageCacheIdentifier: String {
        inboxId
    }
}

extension Conversation: ImageCacheable {
    public var imageCacheIdentifier: String {
        id
    }
}

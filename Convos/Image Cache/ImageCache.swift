import Combine
import Observation
import SwiftUI

// MARK: - Conversation-Based Image Cache
/// Smart reactive image cache that stores images by conversation ID for instant updates across all views.
/// When a new image is uploaded for a conversation, all views showing that conversation update instantly.
@Observable
final class ImageCache {
    static let shared: ImageCache = ImageCache()

    private let identifierCache: NSCache<NSString, UIImage>
    private let urlCache: NSCache<NSString, UIImage>
    private let conversationCache: NSCache<NSString, UIImage>
    private var cacheUpdateSubject: PassthroughSubject<String, Never> = PassthroughSubject<String, Never>()

    var cacheUpdates: AnyPublisher<String, Never> {
        cacheUpdateSubject.eraseToAnyPublisher()
    }

    // This property triggers view updates when changed
    var lastUpdateTime: Date = Date()

    private init() {
        identifierCache = NSCache<NSString, UIImage>()
        identifierCache.countLimit = 200
        identifierCache.totalCostLimit = 100 * 1024 * 1024 // 100MB for identifier cache

        urlCache = NSCache<NSString, UIImage>()
        urlCache.countLimit = 200
        urlCache.totalCostLimit = 100 * 1024 * 1024 // 100MB for URL cache

        conversationCache = NSCache<NSString, UIImage>()
        conversationCache.countLimit = 200
        conversationCache.totalCostLimit = 100 * 1024 * 1024 // 100MB for conversation cache
    }

    func image(for identifier: String) -> UIImage? {
        return identifierCache.object(forKey: identifier as NSString)
    }

    func cacheImage(_ image: UIImage, for identifier: String) {
        cacheImage(image, key: identifier, cache: identifierCache, logContext: "Identifier cache")
    }

    func image(for url: URL) -> UIImage? {
        return urlCache.object(forKey: url.absoluteString as NSString)
    }

    private func cacheImage(_ image: UIImage, key: String, cache: NSCache<NSString, UIImage>, logContext: String) {
        let resizedImage = ImageCompression.resizeForCache(image)

        guard resizedImage.size.width > 0 && resizedImage.size.height > 0 else {
            Logger.error("Failed to resize image for \(logContext): \(key) - invalid dimensions")
            return
        }

        let cost = Int(resizedImage.size.width * resizedImage.size.height * 4)
        cache.setObject(resizedImage, forKey: key as NSString, cost: cost)
        Logger.info("Successfully cached resized image for \(logContext): \(key)")
    }

    func setImage(_ image: UIImage, for url: String) {
        cacheImage(image, key: url, cache: urlCache, logContext: "URL cache")
        lastUpdateTime = Date()
    }

    // Get the latest image for a conversation, regardless of URL
    func imageForConversation(_ conversationId: String) -> UIImage? {
        return conversationCache.object(forKey: conversationId as NSString)
    }

    /// Set the image for a conversation
    /// This triggers instant updates in all views showing this conversation
    func setImageForConversation(_ image: UIImage, conversationId: String) {
        cacheImage(image, key: conversationId, cache: conversationCache, logContext: "conversation cache")
        cacheUpdateSubject.send(conversationId)
        lastUpdateTime = Date()
    }

    /// Remove the cached image for a conversation
    /// This triggers instant updates in all views showing this conversation
    func removeImageForConversation(_ conversationId: String) {
        conversationCache.removeObject(forKey: conversationId as NSString)
        // Notify all views that this conversation's image was removed
        cacheUpdateSubject.send(conversationId)
        lastUpdateTime = Date()
    }
}

import Combine
import ConvosCore
import Observation
import SwiftUI

// MARK: - ImageCacheable Protocol

/// Protocol for objects that can have their images cached
protocol ImageCacheable {
    /// Unique identifier used for caching the image
    var imageCacheIdentifier: String { get }
}

// MARK: - Generic Image Cache

/// Smart reactive image cache that stores images for any ImageCacheable object with instant updates.
/// When a new image is uploaded for an object, all views showing that object update instantly.
@Observable
final class ImageCache {
    static let shared: ImageCache = ImageCache()

    private let cache: NSCache<NSString, UIImage>
    private let urlCache: NSCache<NSString, UIImage>

    /// Publisher for specific cache updates by identifier
    private let cacheUpdateSubject: PassthroughSubject<String, Never> = PassthroughSubject<String, Never>()

    /// Publisher that emits when a specific cached image is updated
    var cacheUpdates: AnyPublisher<String, Never> {
        cacheUpdateSubject.receive(on: DispatchQueue.main).eraseToAnyPublisher()
    }

    private init() {
        cache = NSCache<NSString, UIImage>()
        cache.countLimit = 400
        cache.totalCostLimit = 200 * 1024 * 1024 // 200MB total

        urlCache = NSCache<NSString, UIImage>()
        urlCache.countLimit = 200
        urlCache.totalCostLimit = 100 * 1024 * 1024 // 100MB for URL cache
    }

    // MARK: - Generic Cache Methods

        /// Get cached image for any ImageCacheable object
    func image(for object: any ImageCacheable) -> UIImage? {
        return cache.object(forKey: object.imageCacheIdentifier as NSString)
    }

    /// Set cached image for any ImageCacheable object
    func setImage(_ image: UIImage, for object: any ImageCacheable) {
        let identifier = object.imageCacheIdentifier
        cacheImage(image, key: identifier, cache: cache, logContext: "Object cache")
        cacheUpdateSubject.send(identifier)
    }

    /// Remove cached image for any ImageCacheable object
    func removeImage(for object: any ImageCacheable) {
        let identifier = object.imageCacheIdentifier
        cache.removeObject(forKey: identifier as NSString)
        cacheUpdateSubject.send(identifier)
    }

    // MARK: - Identifier-based Methods

    /// Get cached image by identifier
    func image(for identifier: String) -> UIImage? {
        return cache.object(forKey: identifier as NSString)
    }

    /// Cache image by identifier
    func cacheImage(_ image: UIImage, for identifier: String) {
        cacheImage(image, key: identifier, cache: cache, logContext: "Identifier cache")
        cacheUpdateSubject.send(identifier)
    }

    /// Remove cached image by identifier
    func removeImage(for identifier: String) {
        cache.removeObject(forKey: identifier as NSString)
        cacheUpdateSubject.send(identifier)
    }

    // MARK: - URL-based Methods (kept for compatibility)

    func image(for url: URL) -> UIImage? {
        return urlCache.object(forKey: url.absoluteString as NSString)
    }

    func setImage(_ image: UIImage, for url: String) {
        cacheImage(image, key: url, cache: urlCache, logContext: "URL cache")
    }

    // MARK: - Private Methods

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
}

// MARK: - SwiftUI View Extension for Easy Image Cache Integration

extension View {
    /// Modifier that subscribes to image cache updates for a specific ImageCacheable object
    func cachedImage(
        for object: any ImageCacheable,
        onChange: @escaping (UIImage?) -> Void
    ) -> some View {
        self
            .onAppear {
                // Load initial cached image
                let image = ImageCache.shared.image(for: object)
                onChange(image)
            }
            .onReceive(
                ImageCache.shared.cacheUpdates
                    .filter { $0 == object.imageCacheIdentifier }
            ) { _ in
                // Update when this specific object's image changes
                let image = ImageCache.shared.image(for: object)
                onChange(image)
            }
    }
}

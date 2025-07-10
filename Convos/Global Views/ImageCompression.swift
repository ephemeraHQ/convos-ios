import UIKit

struct ImageCompression {
    static let cacheOptimizedSize: CGFloat = 500

    /// Resizes image for cache storage with optimal dimensions (500×500px default)
    /// - Parameters:
    ///   - image: The original UIImage to resize
    ///   - maxSize: Maximum dimensions (default: 500×500px for cache optimization)
    /// - Returns: Resized UIImage
    static func resizeForCache(
        _ image: UIImage,
        maxSize: CGSize = CGSize(width: cacheOptimizedSize, height: cacheOptimizedSize)
    ) -> UIImage {
        let size = image.size

        // If image is already smaller than max size, return as-is
        if size.width <= maxSize.width && size.height <= maxSize.height {
            return image
        }

        // Calculate scale factor to fit within max size while maintaining aspect ratio
        let widthRatio = maxSize.width / size.width
        let heightRatio = maxSize.height / size.height
        let scaleFactor = min(widthRatio, heightRatio)

        let newSize = CGSize(
            width: size.width * scaleFactor,
            height: size.height * scaleFactor
        )

        // Create resized image with high quality
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { context in
            context.cgContext.interpolationQuality = .high
            context.cgContext.setShouldAntialias(true)
            context.cgContext.setAllowsAntialiasing(true)
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

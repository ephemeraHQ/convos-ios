import UIKit
import SwiftUI

struct ImageCompression {
    static let maxDimension: CGFloat = 1024
    static let jpegQuality: CGFloat = 0.8

    /// Compresses and resizes a UIImage to fit within maxDimension while maintaining aspect ratio
    /// - Parameters:
    ///   - image: The original UIImage to compress
    ///   - maxDimension: Maximum width or height (default: 1024px)
    ///   - quality: JPEG compression quality (default: 0.8)
    /// - Returns: Compressed image data as Data
    static func compressImage(
        _ image: UIImage,
        maxDimension: CGFloat = ImageCompression.maxDimension,
        quality: CGFloat = ImageCompression.jpegQuality
    ) -> Data? {
        // Calculate new size while maintaining aspect ratio
        let newSize = calculateResizeSize(for: image.size, maxDimension: maxDimension)

        // Resize the image
        guard let resizedImage = resizeImage(image, to: newSize) else {
            return nil
        }

        // Convert to JPEG data with compression
        return resizedImage.jpegData(compressionQuality: quality)
    }

    /// Calculates the new size for an image to fit within maxDimension while maintaining aspect ratio
    /// - Parameters:
    ///   - originalSize: The original image size
    ///   - maxDimension: Maximum allowed width or height
    /// - Returns: New CGSize that fits within the constraints
    static func calculateResizeSize(for originalSize: CGSize, maxDimension: CGFloat) -> CGSize {
        let width = originalSize.width
        let height = originalSize.height

        // If both dimensions are already smaller than max, return original size
        if width <= maxDimension && height <= maxDimension {
            return originalSize
        }

        // Calculate scale factor based on the larger dimension
        let scaleFactor = min(maxDimension / width, maxDimension / height)

        return CGSize(
            width: width * scaleFactor,
            height: height * scaleFactor
        )
    }

    /// Resizes a UIImage to the specified size using high-quality rendering
    /// - Parameters:
    ///   - image: The original UIImage
    ///   - newSize: The target size
    /// - Returns: Resized UIImage or nil if failed
    static func resizeImage(_ image: UIImage, to newSize: CGSize) -> UIImage? {
        // Use UIGraphicsImageRenderer for better performance and quality
        let renderer = UIGraphicsImageRenderer(size: newSize)

        return renderer.image { context in
            // Set high quality rendering
            context.cgContext.interpolationQuality = .high
            context.cgContext.setShouldAntialias(true)
            context.cgContext.setAllowsAntialiasing(true)

            // Draw the image in the new size
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// Compresses image data with progressive quality reduction until it fits within size limit
    /// - Parameters:
    ///   - image: The UIImage to compress
    ///   - maxFileSize: Maximum file size in bytes
    ///   - maxDimension: Maximum width or height
    /// - Returns: Compressed image data that fits within size limit
    static func compressImageToSize(
        _ image: UIImage,
        maxFileSize: Int,
        maxDimension: CGFloat = ImageCompression.maxDimension
    ) -> Data? {
        // First resize to max dimensions
        let newSize = calculateResizeSize(for: image.size, maxDimension: maxDimension)
        guard let resizedImage = resizeImage(image, to: newSize) else {
            return nil
        }

        // Try different quality levels until we fit within size limit
        let qualityLevels: [CGFloat] = [0.9, 0.8, 0.7, 0.6, 0.5, 0.4, 0.3, 0.2, 0.1]

        for quality in qualityLevels {
            if let data = resizedImage.jpegData(compressionQuality: quality),
               data.count <= maxFileSize {
                return data
            }
        }

        // If still too large, try reducing dimensions further
        var currentDimension = maxDimension * 0.8
        while currentDimension > 256 {
            let smallerSize = calculateResizeSize(for: image.size, maxDimension: currentDimension)
            if let smallerImage = resizeImage(image, to: smallerSize),
               let data = smallerImage.jpegData(compressionQuality: 0.5),
               data.count <= maxFileSize {
                return data
            }
            currentDimension *= 0.8
        }

        // Last resort: very small image with low quality
        let tinySize = calculateResizeSize(for: image.size, maxDimension: 256)
        if let tinyImage = resizeImage(image, to: tinySize) {
            return tinyImage.jpegData(compressionQuality: 0.1)
        }

        return nil
    }

    /// Utility function to format file size for debugging
    static func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

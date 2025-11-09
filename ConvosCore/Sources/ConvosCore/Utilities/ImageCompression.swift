import CoreGraphics
import ImageIO
import UIKit

struct ImageCompression {
    static let cacheOptimizedSize: CGFloat = 500

    /// Resizes and compresses image to JPEG data in a single pass for optimal performance
    /// This avoids creating an intermediate UIImage, reducing memory usage and improving speed
    /// - Parameters:
    ///   - image: The original UIImage to resize and compress
    ///   - maxSize: Maximum dimensions in points (default: 500×500pt for cache optimization)
    ///   - compressionQuality: JPEG compression quality (0.0-1.0, default: 0.8)
    /// - Returns: JPEG data of the resized and compressed image, or nil if compression fails
    static func resizeAndCompressToJPEG(
        _ image: UIImage,
        maxSize: CGSize = CGSize(width: cacheOptimizedSize, height: cacheOptimizedSize),
        compressionQuality: CGFloat = 0.8
    ) -> Data? {
        // Create JPEG data directly from resized image using Core Graphics
        // This avoids creating an intermediate UIImage
        guard let cgImage = image.cgImage else {
            return nil
        }

        // Work in pixel space: CGImage dimensions are in pixels, not points
        // UIImage.size is in points and doesn't account for scale factor
        let pixelWidth = CGFloat(cgImage.width)
        let pixelHeight = CGFloat(cgImage.height)

        // Convert maxSize from points to pixels using image scale
        // Use scale of 1.0 if image.scale is 0 (can happen with some images)
        let imageScale = image.scale > 0 ? image.scale : 1.0
        let maxPixelWidth = maxSize.width * imageScale
        let maxPixelHeight = maxSize.height * imageScale

        // Calculate target size in pixels
        let targetPixelSize: CGSize
        if pixelWidth <= maxPixelWidth && pixelHeight <= maxPixelHeight {
            // Image is already small enough, use original pixel size
            targetPixelSize = CGSize(width: pixelWidth, height: pixelHeight)
        } else {
            // Calculate scale factor to fit within max size while maintaining aspect ratio
            let widthRatio = maxPixelWidth / pixelWidth
            let heightRatio = maxPixelHeight / pixelHeight
            let scaleFactor = min(widthRatio, heightRatio)

            targetPixelSize = CGSize(
                width: pixelWidth * scaleFactor,
                height: pixelHeight * scaleFactor
            )
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        // Create context with pixel dimensions (CGContext works in pixels, not points)
        guard let context = CGContext(
            data: nil,
            width: Int(targetPixelSize.width),
            height: Int(targetPixelSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return nil
        }

        // Set high-quality rendering
        context.interpolationQuality = .high
        context.setShouldAntialias(true)
        context.setAllowsAntialiasing(true)

        // Apply orientation transform to respect EXIF orientation data
        // This ensures images from cameras display correctly
        let orientation = image.imageOrientation
        context.saveGState()

        // Calculate the transform and adjusted drawing rect based on orientation
        // Use pixel dimensions for both source and target
        let (transform, drawingRect) = orientationTransformAndRect(
            orientation: orientation,
            imageSize: CGSize(width: pixelWidth, height: pixelHeight),
            targetSize: targetPixelSize
        )

        context.concatenate(transform)

        // Draw the image scaled to target size with proper orientation
        context.draw(cgImage, in: drawingRect)

        context.restoreGState()

        // Get the resized image from context
        guard let resizedCGImage = context.makeImage() else {
            return nil
        }

        // Use ImageIO to compress directly to JPEG data without creating UIImage
        // This is more memory-efficient than using UIImage.jpegData()
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutableData, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }

        // Set JPEG compression quality
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: compressionQuality
        ]

        CGImageDestinationAddImage(destination, resizedCGImage, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return mutableData as Data
    }

    /// Resizes and compresses image to PNG data in a single pass for optimal performance
    /// This preserves alpha channel and is lossless, making it ideal for images with transparency
    /// - Parameters:
    ///   - image: The original UIImage to resize and compress
    ///   - maxSize: Maximum dimensions in points (default: 500×500pt for cache optimization)
    /// - Returns: PNG data of the resized and compressed image, or nil if compression fails
    static func resizeAndCompressToPNG(
        _ image: UIImage,
        maxSize: CGSize = CGSize(width: cacheOptimizedSize, height: cacheOptimizedSize)
    ) -> Data? {
        // Create PNG data directly from resized image using Core Graphics
        // This avoids creating an intermediate UIImage
        guard let cgImage = image.cgImage else {
            return nil
        }

        // Work in pixel space: CGImage dimensions are in pixels, not points
        // UIImage.size is in points and doesn't account for scale factor
        let pixelWidth = CGFloat(cgImage.width)
        let pixelHeight = CGFloat(cgImage.height)

        // Convert maxSize from points to pixels using image scale
        // Use scale of 1.0 if image.scale is 0 (can happen with some images)
        let imageScale = image.scale > 0 ? image.scale : 1.0
        let maxPixelWidth = maxSize.width * imageScale
        let maxPixelHeight = maxSize.height * imageScale

        // Calculate target size in pixels
        let targetPixelSize: CGSize
        if pixelWidth <= maxPixelWidth && pixelHeight <= maxPixelHeight {
            // Image is already small enough, use original pixel size
            targetPixelSize = CGSize(width: pixelWidth, height: pixelHeight)
        } else {
            // Calculate scale factor to fit within max size while maintaining aspect ratio
            let widthRatio = maxPixelWidth / pixelWidth
            let heightRatio = maxPixelHeight / pixelHeight
            let scaleFactor = min(widthRatio, heightRatio)

            targetPixelSize = CGSize(
                width: pixelWidth * scaleFactor,
                height: pixelHeight * scaleFactor
            )
        }

        // Use RGB color space with alpha channel support
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        // Create context with pixel dimensions (CGContext works in pixels, not points)
        guard let context = CGContext(
            data: nil,
            width: Int(targetPixelSize.width),
            height: Int(targetPixelSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return nil
        }

        // Set high-quality rendering
        context.interpolationQuality = .high
        context.setShouldAntialias(true)
        context.setAllowsAntialiasing(true)

        // Apply orientation transform to respect EXIF orientation data
        // This ensures images from cameras display correctly
        let orientation = image.imageOrientation
        context.saveGState()

        // Calculate the transform and adjusted drawing rect based on orientation
        // Use pixel dimensions for both source and target
        let (transform, drawingRect) = orientationTransformAndRect(
            orientation: orientation,
            imageSize: CGSize(width: pixelWidth, height: pixelHeight),
            targetSize: targetPixelSize
        )

        context.concatenate(transform)

        // Draw the image scaled to target size with proper orientation
        context.draw(cgImage, in: drawingRect)

        context.restoreGState()

        // Get the resized image from context
        guard let resizedCGImage = context.makeImage() else {
            return nil
        }

        // Use ImageIO to compress directly to PNG data without creating UIImage
        // PNG is lossless and preserves alpha channel
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutableData, "public.png" as CFString, 1, nil) else {
            return nil
        }

        // PNG compression options (lossless)
        let options: [CFString: Any] = [:]

        CGImageDestinationAddImage(destination, resizedCGImage, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return mutableData as Data
    }

    /// Checks if an image has transparency (alpha channel)
    /// - Parameter image: The UIImage to check
    /// - Returns: true if the image has transparency, false otherwise
    static func hasTransparency(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else {
            return false
        }

        let alphaInfo = cgImage.alphaInfo

        // Check if the image format supports alpha
        switch alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly:
            // Format supports alpha, but we need to check if there are actually transparent pixels
            return checkForTransparentPixels(cgImage: cgImage)
        @unknown default:
            // For unknown formats, assume no transparency to be safe
            return false
        }
    }

    /// Checks if a CGImage actually contains transparent pixels
    /// - Parameter cgImage: The CGImage to check
    /// - Returns: true if transparent pixels are found, false otherwise
    private static func checkForTransparentPixels(cgImage: CGImage) -> Bool {
        let width = cgImage.width
        let height = cgImage.height

        // Sample a subset of pixels to check for transparency (for performance)
        // For QR codes, we can be more thorough since they're typically small
        let sampleStep = max(1, min(width, height) / 50) // Sample every Nth pixel, or all if small

        // Rasterize into a known RGBA bitmap format to avoid byte order issues
        // Use premultipliedLast (RGBA) format where alpha is always at offset 3
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return false
        }

        // Draw the image into the context
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Get the bitmap data from the context
        guard let data = context.data else {
            return false
        }

        let bytesPerPixel = 4 // RGBA = 4 bytes per pixel
        let bytesPerRow = context.bytesPerRow

        // Sample pixels to check for transparency
        // In RGBA format, alpha is always at offset 3 (last byte)
        for y in stride(from: 0, to: height, by: sampleStep) {
            for x in stride(from: 0, to: width, by: sampleStep) {
                let pixelOffset = y * bytesPerRow + x * bytesPerPixel + 3 // Alpha is at offset 3 in RGBA
                guard pixelOffset < bytesPerRow * height else { continue }

                let alpha = data.advanced(by: pixelOffset).assumingMemoryBound(to: UInt8.self).pointee
                // If we find any pixel with alpha < 255, the image has transparency
                if alpha < 255 {
                    return true
                }
            }
        }

        return false
    }

    /// Calculates the transform and drawing rect needed to apply UIImage orientation
    /// - Parameters:
    ///   - orientation: The UIImage orientation
    ///   - imageSize: The original image size in pixels
    ///   - targetSize: The target size for the resized image in pixels
    /// - Returns: A tuple containing the CGAffineTransform and the drawing rect (in pixels)
    private static func orientationTransformAndRect(
        orientation: UIImage.Orientation,
        imageSize: CGSize,
        targetSize: CGSize
    ) -> (transform: CGAffineTransform, rect: CGRect) {
        let width = targetSize.width
        let height = targetSize.height

        switch orientation {
        case .up:
            // No transformation needed
            return (.identity, CGRect(origin: .zero, size: targetSize))

        case .upMirrored:
            // Flip horizontally
            var transform = CGAffineTransform(translationX: width, y: 0)
            transform = transform.scaledBy(x: -1, y: 1)
            return (transform, CGRect(origin: .zero, size: targetSize))

        case .down:
            // Rotate 180 degrees
            var transform = CGAffineTransform(translationX: width, y: height)
            transform = transform.rotated(by: .pi)
            return (transform, CGRect(origin: .zero, size: targetSize))

        case .downMirrored:
            // Flip vertically
            var transform = CGAffineTransform(translationX: 0, y: height)
            transform = transform.scaledBy(x: 1, y: -1)
            return (transform, CGRect(origin: .zero, size: targetSize))

        case .left:
            // Rotate 90 degrees counterclockwise (swap width/height)
            var transform = CGAffineTransform(translationX: 0, y: width)
            transform = transform.rotated(by: -.pi / 2)
            return (transform, CGRect(origin: .zero, size: CGSize(width: height, height: width)))

        case .leftMirrored:
            // Rotate 90 degrees counterclockwise and flip horizontally
            var transform = CGAffineTransform(translationX: height, y: width)
            transform = transform.scaledBy(x: -1, y: 1)
            transform = transform.rotated(by: -.pi / 2)
            return (transform, CGRect(origin: .zero, size: CGSize(width: height, height: width)))

        case .right:
            // Rotate 90 degrees clockwise (swap width/height)
            var transform = CGAffineTransform(translationX: height, y: 0)
            transform = transform.rotated(by: .pi / 2)
            return (transform, CGRect(origin: .zero, size: CGSize(width: height, height: width)))

        case .rightMirrored:
            // Rotate 90 degrees clockwise and flip horizontally
            var transform = CGAffineTransform(translationX: height, y: 0)
            transform = transform.scaledBy(x: -1, y: 1)
            transform = transform.rotated(by: .pi / 2)
            return (transform, CGRect(origin: .zero, size: CGSize(width: height, height: width)))

        @unknown default:
            // Fallback to no transformation for unknown orientations
            return (.identity, CGRect(origin: .zero, size: targetSize))
        }
    }
}

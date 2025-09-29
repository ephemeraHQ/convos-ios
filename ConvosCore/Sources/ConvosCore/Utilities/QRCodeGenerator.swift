import CoreImage.CIFilterBuiltins
import Foundation
import UIKit

/// A reusable QR code generator that can be used throughout the app
///
/// This generator automatically caches generated QR codes based on their content and options.
/// Different options (colors, size, etc.) for the same content will be cached separately.
public enum QRCodeGenerator {
    public struct Options {
        /// The scale factor to use for rendering (defaults to main screen scale)
        public let scale: CGFloat
        /// The target display size in points
        public let displaySize: CGFloat
        /// Whether to use rounded markers
        public let roundedMarkers: Bool
        /// Whether to use rounded data cells
        public let roundedData: Bool
        /// The size of the center space (0.0 to 1.0)
        public let centerSpaceSize: Float
        /// Error correction level: "L", "M", "Q", "H"
        public let correctionLevel: String
        /// Foreground color
        public let foregroundColor: CIColor
        /// Background color
        public let backgroundColor: CIColor

        public init(
            scale: CGFloat? = nil,
            displaySize: CGFloat = 220,
            roundedMarkers: Bool = true,
            roundedData: Bool = true,
            centerSpaceSize: Float = 0.25,
            correctionLevel: String = "Q",
            foregroundColor: UIColor = .black,
            backgroundColor: UIColor = .white
        ) {
            self.scale = scale ?? 3.0 // Default to 3x if not provided
            self.displaySize = displaySize
            self.roundedMarkers = roundedMarkers
            self.roundedData = roundedData
            self.centerSpaceSize = centerSpaceSize
            self.correctionLevel = correctionLevel
            self.foregroundColor = CIColor(color: foregroundColor)
            self.backgroundColor = CIColor(color: backgroundColor)
        }

        /// Configuration for QR codes in light mode
        public static var qrCodeLight: Options {
            Options(
                scale: 3.0, // Default to 3x for retina displays
                displaySize: 220,
                foregroundColor: .black, // Dark QR code
                backgroundColor: .clear  // Light background
            )
        }

        /// Configuration for QR codes in dark mode
        public static var qrCodeDark: Options {
            Options(
                scale: 3.0, // Default to 3x for retina displays
                displaySize: 220,
                foregroundColor: .white, // Light QR code
                backgroundColor: .clear  // Dark background
            )
        }
    }

    /// Custom hash key for options that includes all relevant properties
    private struct OptionsHashKey: Hashable {
        let scale: CGFloat
        let displaySize: CGFloat
        let roundedMarkers: Bool
        let roundedData: Bool
        let centerSpaceSize: Float
        let correctionLevel: String
        let foregroundRed: CGFloat
        let foregroundGreen: CGFloat
        let foregroundBlue: CGFloat
        let foregroundAlpha: CGFloat
        let backgroundRed: CGFloat
        let backgroundGreen: CGFloat
        let backgroundBlue: CGFloat
        let backgroundAlpha: CGFloat

        init(options: Options) {
            self.scale = options.scale
            self.displaySize = options.displaySize
            self.roundedMarkers = options.roundedMarkers
            self.roundedData = options.roundedData
            self.centerSpaceSize = options.centerSpaceSize
            self.correctionLevel = options.correctionLevel
            self.foregroundRed = options.foregroundColor.red
            self.foregroundGreen = options.foregroundColor.green
            self.foregroundBlue = options.foregroundColor.blue
            self.foregroundAlpha = options.foregroundColor.alpha
            self.backgroundRed = options.backgroundColor.red
            self.backgroundGreen = options.backgroundColor.green
            self.backgroundBlue = options.backgroundColor.blue
            self.backgroundAlpha = options.backgroundColor.alpha
        }
    }

    /// Creates a cache key based on the string and options
    private static func cacheKey(for string: String, options: Options) -> String {
        var hasher = Hasher()
        hasher.combine(string)
        hasher.combine(OptionsHashKey(options: options))
        return "qr_\(hasher.finalize())"
    }

    /// Generates a QR code image from the given string
    /// - Parameters:
    ///   - from: The string to encode
    ///   - options: Generation options
    /// - Returns: The generated QR code image, or nil if generation fails
    public static func generate(from string: String, options: Options = .init()) -> UIImage? {
        let cacheKey = cacheKey(for: string, options: options)

        // Check cache first
        if let cachedImage = ImageCache.shared.image(for: cacheKey) {
            return cachedImage
        }

        let context = CIContext()
        let filter = CIFilter.roundedQRCodeGenerator()

        filter.message = Data(string.utf8)
        filter.roundedMarkers = options.roundedMarkers ? 1 : 0
        filter.roundedData = options.roundedData
        filter.centerSpaceSize = options.centerSpaceSize
        filter.correctionLevel = options.correctionLevel
        filter.color1 = options.foregroundColor
        filter.color0 = options.backgroundColor

        guard let outputImage = filter.outputImage else { return nil }

        let outputExtent = outputImage.extent
        let baseSize = max(outputExtent.width, outputExtent.height)

        // Scale to match the display size * scale factor
        let targetPixelSize = options.displaySize * options.scale
        let scaleFactor = targetPixelSize / baseSize

        let transform = CGAffineTransform(scaleX: scaleFactor, y: scaleFactor)
        let scaledImage = outputImage.transformed(by: transform)

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        let image = UIImage(cgImage: cgImage, scale: options.scale, orientation: .up)

        // Cache the generated image
        ImageCache.shared.cacheImage(image, for: cacheKey)

        return image
    }

    /// Generates a QR code asynchronously
    /// - Parameters:
    ///   - from: The string to encode
    ///   - options: Generation options
    /// - Returns: The generated QR code image, or nil if generation fails
    public static func generate(from string: String, options: Options = .init()) async -> UIImage? {
        let cacheKey = cacheKey(for: string, options: options)

        // Check cache first
        if let cachedImage = ImageCache.shared.image(for: cacheKey) {
            return cachedImage
        }

        // Generate in background
        return await Task.detached(priority: .userInitiated) {
            generate(from: string, options: options)
        }.value
    }

    /// Pre-generates QR codes for both light and dark modes
    /// - Parameters:
    ///   - string: The string to encode
    ///   - scale: Optional scale factor (defaults to 3.0)
    /// - Returns: Tuple of (lightModeImage, darkModeImage)
    public static func pregenerate(from string: String, scale: CGFloat = 3.0) async -> (light: UIImage?, dark: UIImage?) {
        let lightOptions = Options(
            scale: scale,
            displaySize: 220,
            foregroundColor: .black,
            backgroundColor: .white
        )

        let darkOptions = Options(
            scale: scale,
            displaySize: 220,
            foregroundColor: .white,
            backgroundColor: .black
        )

        async let lightImage = generate(from: string, options: lightOptions)
        async let darkImage = generate(from: string, options: darkOptions)

        return await (lightImage, darkImage)
    }

    /// Clears a specific QR code from the cache
    /// - Parameters:
    ///   - string: The string content of the QR code
    ///   - options: The options used to generate the QR code
    public static func clearFromCache(string: String, options: Options = .init()) {
        let cacheKey = cacheKey(for: string, options: options)
        ImageCache.shared.removeImage(for: cacheKey)
    }

    /// Clears QR codes for both light and dark modes from cache
    /// - Parameter string: The string content of the QR code
    public static func clearFromCacheAllModes(string: String) {
        clearFromCache(string: string, options: Options.qrCodeLight)
        clearFromCache(string: string, options: Options.qrCodeDark)
    }
}

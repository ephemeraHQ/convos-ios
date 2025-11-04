import Compression
import Foundation

/// DEFLATE compression utilities for protobuf payloads
///
/// Used by SignedInvite and ConversationCustomMetadata to reduce size by 20-40%.
///
/// **Compressed Format:** `[marker: 1 byte][size: 4 bytes][compressed data]`
///
/// **Usage:**
/// ```swift
/// // Compression
/// let compressed = data.compressedIfSmaller()
///
/// // Decompression (caller strips marker first)
/// if data.first == Data.compressionMarker {
///     let decompressed = data.dropFirst().decompressedWithSize(maxSize: limit)
/// }
/// ```
extension Data {
    /// Magic byte prefix for compressed data
    static let compressionMarker: UInt8 = 0x1F

    /// Compress data using DEFLATE, only if result is smaller than input
    /// - Parameter marker: Optional compression marker byte (defaults to standard marker)
    /// - Returns: Compressed data with metadata, or nil if compression doesn't reduce size
    func compressedIfSmaller(marker: UInt8 = Data.compressionMarker) -> Data? {
        guard let compressed = compressedWithSize(marker: marker), compressed.count < count else {
            return nil
        }
        return compressed
    }

    /// Compress data using DEFLATE and prepend format metadata
    /// - Parameter marker: Compression marker byte to prepend
    /// - Returns: Compressed data in format: [marker: 1 byte][size: 4 bytes big-endian][compressed data]
    func compressedWithSize(marker: UInt8 = Data.compressionMarker) -> Data? {
        return self.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return nil }

            let sourceBuffer = UnsafeBufferPointer<UInt8>(
                start: baseAddress.assumingMemoryBound(to: UInt8.self),
                count: count
            )

            let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
            defer { destinationBuffer.deallocate() }

            guard let baseAddress = sourceBuffer.baseAddress else { return nil }

            let compressedSize = compression_encode_buffer(
                destinationBuffer, count,
                baseAddress, count,
                nil, COMPRESSION_ZLIB
            )

            guard compressedSize > 0 else { return nil }

            var result = Data()
            result.append(marker)

            // Store original size as UInt32 big-endian
            // validate count fits in UInt32 to prevent integer overflow
            guard count <= Int(UInt32.max) else {
                return nil
            }
            let size = UInt32(count)
            result.append(contentsOf: [
                UInt8((size >> 24) & 0xFF),
                UInt8((size >> 16) & 0xFF),
                UInt8((size >> 8) & 0xFF),
                UInt8(size & 0xFF)
            ])

            result.append(Data(bytes: destinationBuffer, count: compressedSize))

            return result
        }
    }

    /// Decompress DEFLATE-compressed data with size metadata
    /// - Parameters:
    ///   - maxSize: Maximum allowed decompressed size to prevent decompression bombs
    ///   - maxCompressionRatio: Maximum allowed compression ratio to detect zip bombs (default: 100)
    /// - Returns: Decompressed data or nil if decompression fails, exceeds limits, or has suspicious compression ratio
    /// - Note: Expected format: [size: 4 bytes big-endian][compressed data] (marker already stripped by caller)
    func decompressedWithSize(maxSize: UInt32, maxCompressionRatio: UInt32 = 100) -> Data? {
        guard count >= 5 else { return nil }

        let sizeBytes = Array(prefix(4))

        let originalSize: UInt32 = (UInt32(sizeBytes[0]) << 24) |
                                    (UInt32(sizeBytes[1]) << 16) |
                                    (UInt32(sizeBytes[2]) << 8) |
                                     UInt32(sizeBytes[3])

        guard originalSize > 0, originalSize <= maxSize else { return nil }

        let compressedData = dropFirst(4)
        guard !compressedData.isEmpty else { return nil }

        // validate compression ratio to prevent zip bombs
        let compressionRatio = originalSize / UInt32(compressedData.count)
        guard compressionRatio <= maxCompressionRatio else { return nil }

        return compressedData.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return nil }

            let sourceBuffer = UnsafeBufferPointer<UInt8>(
                start: baseAddress.assumingMemoryBound(to: UInt8.self),
                count: compressedData.count
            )

            guard let sourceBaseAddress = sourceBuffer.baseAddress else { return nil }

            let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(originalSize))
            defer { destinationBuffer.deallocate() }

            let decompressedSize = compression_decode_buffer(
                destinationBuffer, Int(originalSize),
                sourceBaseAddress, compressedData.count,
                nil, COMPRESSION_ZLIB
            )

            guard decompressedSize > 0, decompressedSize == Int(originalSize) else {
                return nil
            }

            return Data(bytes: destinationBuffer, count: decompressedSize)
        }
    }
}

import Compression
import Foundation

extension Data {
    /// Magic byte prefix for compressed data
    static let compressionMarker: UInt8 = 0x1F

    /// Compress data using zlib deflate with size metadata, only if result is smaller
    /// - Parameter marker: Optional compression marker byte (defaults to standard marker)
    /// - Returns: Compressed data with metadata, or nil if compression doesn't reduce size
    func compressedIfSmaller(marker: UInt8 = Data.compressionMarker) -> Data? {
        guard let compressed = compressedWithSize(marker: marker), compressed.count < count else {
            return nil
        }
        return compressed
    }

    /// Compress data using zlib deflate and prepend format metadata
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

    /// Decompress data using zlib inflate with size metadata
    /// - Parameter maxSize: Maximum allowed decompressed size (safety limit)
    /// - Returns: Decompressed data or nil if decompression fails or exceeds maxSize
    /// - Note: Expected format: [marker: 1 byte][size: 4 bytes big-endian][compressed data]
    func decompressedWithSize(maxSize: UInt32) -> Data? {
        guard count >= 6 else { return nil }

        let dataAfterMarker = self.dropFirst()

        guard dataAfterMarker.count >= 4 else { return nil }
        let sizeBytes = Array(dataAfterMarker.prefix(4))

        let originalSize: UInt32 = (UInt32(sizeBytes[0]) << 24) |
                                    (UInt32(sizeBytes[1]) << 16) |
                                    (UInt32(sizeBytes[2]) << 8) |
                                     UInt32(sizeBytes[3])

        guard originalSize > 0, originalSize <= maxSize else { return nil }

        let compressedData = dataAfterMarker.dropFirst(4)
        guard !compressedData.isEmpty else { return nil }

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

@testable import ConvosCore
import Foundation
import Testing

/// Comprehensive tests for Data+Compression.swift
///
/// Tests cover:
/// - Compression/decompression round-trip
/// - Edge cases (empty, small, threshold-sized data)
/// - Decompression bomb protection
/// - Invalid compressed data handling
/// - Compression ratio limits
@Suite("Data Compression Tests")
struct DataCompressionTests {
    // MARK: - Round-Trip Tests

    @Test("Compression round-trip preserves data")
    func compressionRoundTrip() throws {
        let testCases: [Data] = [
            Data(repeating: 0x42, count: 500),
            Data((0..<1000).map { UInt8($0 % 256) }),
            "Hello World! ".data(using: .utf8)!.repeatData(count: 50)
        ]

        for originalData in testCases {
            guard let compressed = originalData.compressedWithSize() else {
                throw TestError("Failed to compress data of size \(originalData.count)")
            }

            // Verify marker is present
            #expect(compressed.first == Data.compressionMarker)

            // Decompress
            let dataWithoutMarker = compressed.dropFirst()
            guard let decompressed = dataWithoutMarker.decompressedWithSize(maxSize: 10 * 1024 * 1024) else {
                throw TestError("Failed to decompress data")
            }

            #expect(decompressed == originalData)
        }
    }

    @Test("compressedIfSmaller only returns data when beneficial")
    func compressionOnlyWhenBeneficial() {
        // Small random data unlikely to compress well
        let randomData = Data((0..<50).map { _ in UInt8.random(in: 0...255) })
        let result = randomData.compressedIfSmaller()

        // May or may not compress - but if it does, must be smaller
        if let compressed = result {
            #expect(compressed.count < randomData.count)
        }

        // Highly compressible data should compress
        let compressibleData = Data(repeating: 0x42, count: 500)
        let compressedResult = compressibleData.compressedIfSmaller()
        #expect(compressedResult != nil)
        #expect(compressedResult!.count < compressibleData.count)
    }

    // MARK: - Threshold Tests

    @Test("Compression threshold behavior")
    func compressionThreshold() {
        // Data below compression threshold (100 bytes as per ConversationCustomMetadata)
        let smallData = Data(repeating: 0x42, count: 50)

        // compressedWithSize should still work
        let compressed = smallData.compressedWithSize()
        #expect(compressed != nil)

        // compressedIfSmaller might return nil if overhead makes it bigger
        // This is expected behavior - no assertion needed, just verify it doesn't crash
        _ = smallData.compressedIfSmaller()

        // Data at threshold
        let thresholdData = Data(repeating: 0x42, count: 100)
        let thresholdCompressed = thresholdData.compressedIfSmaller()
        // Should compress well due to repetition
        #expect(thresholdCompressed != nil)

        // Data above threshold
        let largeData = Data(repeating: 0x42, count: 200)
        let largeCompressed = largeData.compressedIfSmaller()
        #expect(largeCompressed != nil)
    }

    // MARK: - Edge Cases

    @Test("Empty data handling")
    func emptyDataHandling() {
        let emptyData = Data()

        // Compression should handle empty data gracefully
        let compressed = emptyData.compressedWithSize()
        // Empty data might not compress or might fail - either is acceptable
        // Just verify it doesn't crash

        if let compressed = compressed {
            // If it did compress, verify structure
            #expect(compressed.count >= 5) // marker + 4-byte size
        }
    }

    @Test("Single byte data")
    func singleByteData() {
        let singleByte = Data([0x42])

        // Should handle single byte without crashing
        _ = singleByte.compressedWithSize()
        _ = singleByte.compressedIfSmaller()
    }

    @Test("Maximum size data (UInt32.max boundary)")
    func maximumSizeHandling() {
        // Test data near UInt32.max boundary (4GB)
        // We can't actually allocate 4GB in a test, so test the boundary check logic
        // by verifying moderate sizes work
        let largeData = Data(repeating: 0x42, count: 100_000)
        let compressed = largeData.compressedWithSize()
        #expect(compressed != nil)
    }

    // MARK: - Decompression Bomb Prevention

    @Test("Decompression bomb protection - size limit")
    func decompressionBombSizeProtection() throws {
        // Create a small compressed payload with a claimed huge decompressed size
        var maliciousData = Data()
        maliciousData.append(Data.compressionMarker)

        // Claim decompressed size is 100MB (over the 10MB limit)
        let fakeSize: UInt32 = 100 * 1024 * 1024
        maliciousData.append(contentsOf: [
            UInt8((fakeSize >> 24) & 0xFF),
            UInt8((fakeSize >> 16) & 0xFF),
            UInt8((fakeSize >> 8) & 0xFF),
            UInt8(fakeSize & 0xFF)
        ])

        // Add some random "compressed" data
        maliciousData.append(Data(repeating: 0x42, count: 100))

        // Should reject due to size limit
        let dataWithoutMarker = maliciousData.dropFirst()
        let result = dataWithoutMarker.decompressedWithSize(maxSize: 10 * 1024 * 1024)
        #expect(result == nil)
    }

    @Test("Decompression bomb protection - compression ratio")
    func decompressionBombRatioProtection() throws {
        // Create data with suspicious compression ratio (>100:1)
        var suspiciousData = Data()
        suspiciousData.append(Data.compressionMarker)

        // Claim decompressed size is 1MB but compressed data is only 10 bytes (100:1 ratio)
        let claimedSize: UInt32 = 1024 * 1024
        suspiciousData.append(contentsOf: [
            UInt8((claimedSize >> 24) & 0xFF),
            UInt8((claimedSize >> 16) & 0xFF),
            UInt8((claimedSize >> 8) & 0xFF),
            UInt8(claimedSize & 0xFF)
        ])

        // Add only 10 bytes of "compressed" data (creates 100:1 ratio)
        suspiciousData.append(Data(repeating: 0x42, count: 10))

        // Should reject due to compression ratio
        let dataWithoutMarker = suspiciousData.dropFirst()
        let result = dataWithoutMarker.decompressedWithSize(maxSize: 10 * 1024 * 1024, maxCompressionRatio: 100)
        #expect(result == nil)
    }

    @Test("Valid high compression ratio accepted")
    func validHighCompressionRatio() throws {
        // Use data with moderate compression (not 100:1)
        // Create semi-repetitive data that compresses well but not extremely
        var semiRepetitive = Data()
        for i in 0..<1000 {
            semiRepetitive.append(UInt8(i % 50)) // Cycles through 50 values
        }

        guard let compressed = semiRepetitive.compressedWithSize() else {
            throw TestError("Failed to compress data")
        }

        let dataWithoutMarker = compressed.dropFirst()
        let decompressed = dataWithoutMarker.decompressedWithSize(maxSize: 10 * 1024 * 1024, maxCompressionRatio: 100)

        #expect(decompressed != nil)
        #expect(decompressed == semiRepetitive)
    }

    // MARK: - Invalid Data Tests

    @Test("Invalid compressed data - truncated size")
    func invalidCompressedDataTruncatedSize() {
        var invalidData = Data()
        invalidData.append(Data.compressionMarker)
        invalidData.append(contentsOf: [0x00, 0x01]) // Only 2 bytes instead of 4

        let dataWithoutMarker = invalidData.dropFirst()
        let result = dataWithoutMarker.decompressedWithSize(maxSize: 1024)
        #expect(result == nil)
    }

    @Test("Invalid compressed data - no size header")
    func invalidCompressedDataNoSize() {
        let invalidData = Data([Data.compressionMarker])

        let dataWithoutMarker = invalidData.dropFirst()
        let result = dataWithoutMarker.decompressedWithSize(maxSize: 1024)
        #expect(result == nil)
    }

    @Test("Invalid compressed data - corrupted payload")
    func invalidCompressedDataCorruptedPayload() {
        var invalidData = Data()
        invalidData.append(Data.compressionMarker)

        // Valid size header claiming 100 bytes
        let size: UInt32 = 100
        invalidData.append(contentsOf: [
            UInt8((size >> 24) & 0xFF),
            UInt8((size >> 16) & 0xFF),
            UInt8((size >> 8) & 0xFF),
            UInt8(size & 0xFF)
        ])

        // Corrupted/invalid compressed data
        invalidData.append(Data(repeating: 0xFF, count: 50))

        let dataWithoutMarker = invalidData.dropFirst()
        let result = dataWithoutMarker.decompressedWithSize(maxSize: 1024)
        #expect(result == nil)
    }

    @Test("Invalid compressed data - zero size")
    func invalidCompressedDataZeroSize() {
        var invalidData = Data()
        invalidData.append(Data.compressionMarker)

        // Zero size
        invalidData.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        invalidData.append(Data(repeating: 0x42, count: 10))

        let dataWithoutMarker = invalidData.dropFirst()
        let result = dataWithoutMarker.decompressedWithSize(maxSize: 1024)
        #expect(result == nil)
    }

    @Test("Invalid compressed data - size mismatch")
    func invalidCompressedDataSizeMismatch() throws {
        // Create valid compressed data
        let originalData = Data(repeating: 0x42, count: 100)
        guard var compressed = originalData.compressedWithSize() else {
            throw TestError("Failed to compress test data")
        }

        // Corrupt the size field to claim wrong size
        compressed[1] = 0xFF // Change size bytes
        compressed[2] = 0xFF
        compressed[3] = 0xFF
        compressed[4] = 0xFF

        let dataWithoutMarker = compressed.dropFirst()
        let result = dataWithoutMarker.decompressedWithSize(maxSize: 10 * 1024 * 1024)
        #expect(result == nil)
    }

    // MARK: - Custom Marker Tests

    @Test("Custom compression marker")
    func customCompressionMarker() throws {
        let testData = Data(repeating: 0x42, count: 200)
        let customMarker: UInt8 = 0x99

        guard let compressed = testData.compressedWithSize(marker: customMarker) else {
            throw TestError("Failed to compress with custom marker")
        }

        #expect(compressed.first == customMarker)

        // Decompression doesn't care about marker (caller strips it)
        let dataWithoutMarker = compressed.dropFirst()
        let decompressed = dataWithoutMarker.decompressedWithSize(maxSize: 1024)

        #expect(decompressed == testData)
    }

    // MARK: - Size Encoding Tests

    @Test("Size encoding round-trip for various sizes")
    func sizeEncodingRoundTrip() throws {
        let testSizes = [1, 100, 1000, 5000]

        for size in testSizes {
            // Use varied data to avoid extreme compression ratios
            var testData = Data()
            for i in 0..<size {
                testData.append(UInt8(i % 256))
            }

            guard let compressed = testData.compressedWithSize() else {
                continue // Some sizes might not compress
            }

            // Extract size from compressed data
            let sizeBytes = Array(compressed.dropFirst().prefix(4))
            let extractedSize: UInt32 = (UInt32(sizeBytes[0]) << 24) |
                                        (UInt32(sizeBytes[1]) << 16) |
                                        (UInt32(sizeBytes[2]) << 8) |
                                         UInt32(sizeBytes[3])

            #expect(extractedSize == UInt32(size))

            // Verify decompression uses this size
            let dataWithoutMarker = compressed.dropFirst()
            let decompressed = dataWithoutMarker.decompressedWithSize(maxSize: 10 * 1024 * 1024)
            #expect(decompressed?.count == size)
        }
    }
}

// MARK: - Helper Extensions

extension Data {
    fileprivate func repeatData(count: Int) -> Data {
        var result = Data()
        for _ in 0..<count {
            result.append(self)
        }
        return result
    }
}

struct TestError: Error, CustomStringConvertible {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var description: String {
        message
    }
}

@testable import ConvosCore
import Foundation
import Testing

/// Comprehensive tests for Data+Hex.swift
///
/// Tests cover:
/// - Hex encoding (uppercase/lowercase)
/// - Hex decoding with various formats
/// - Edge cases (empty strings, odd-length strings, invalid characters)
/// - 32-byte validation for inbox IDs
/// - Round-trip conversion
@Suite("Data Hex Encoding/Decoding Tests")
struct DataHexTests {
    // MARK: - Encoding Tests

    @Test("Hex encoding lowercase")
    func hexEncodingLowercase() {
        let testCases: [(Data, String)] = [
            (Data([0x00, 0x01, 0x02, 0x03]), "00010203"),
            (Data([0xAB, 0xCD, 0xEF]), "abcdef"),
            (Data([0xFF, 0xFF]), "ffff"),
            (Data([0x00]), "00"),
            (Data(), "")
        ]

        for (data, expectedHex) in testCases {
            let encoded = data.hexEncodedString()
            #expect(encoded == expectedHex)

            let encodedAlt = data.toHex
            #expect(encodedAlt == expectedHex)
        }
    }

    @Test("Hex encoding uppercase")
    func hexEncodingUppercase() {
        let testCases: [(Data, String)] = [
            (Data([0x00, 0x01, 0x02, 0x03]), "00010203"),
            (Data([0xAB, 0xCD, 0xEF]), "ABCDEF"),
            (Data([0xFF, 0xFF]), "FFFF"),
            (Data([0x00]), "00")
        ]

        for (data, expectedHex) in testCases {
            let encoded = data.hexEncodedString(options: .upperCase)
            #expect(encoded == expectedHex)
        }
    }

    @Test("Hex encoding for 32-byte inbox ID")
    func hexEncodingInboxId() {
        // Simulate a 32-byte inbox ID
        let inboxIdBytes = Data((0..<32).map { UInt8($0) })
        let hex = inboxIdBytes.hexEncodedString()

        // Should produce 64 characters
        #expect(hex.count == 64)

        // Verify it's all valid hex characters
        let hexCharSet = CharacterSet(charactersIn: "0123456789abcdef")
        #expect(hex.rangeOfCharacter(from: hexCharSet.inverted) == nil)
    }

    // MARK: - Decoding Tests

    @Test("Hex decoding valid strings")
    func hexDecodingValid() {
        let testCases: [(String, Data)] = [
            ("00010203", Data([0x00, 0x01, 0x02, 0x03])),
            ("abcdef", Data([0xAB, 0xCD, 0xEF])),
            ("ABCDEF", Data([0xAB, 0xCD, 0xEF])),
            ("ffff", Data([0xFF, 0xFF])),
            ("00", Data([0x00])),
            ("", Data())
        ]

        for (hexString, expectedData) in testCases {
            let decoded = Data(hexString: hexString)
            #expect(decoded == expectedData)
        }
    }

    @Test("Hex decoding with 0x prefix")
    func hexDecodingWithPrefix() {
        let testCases: [(String, Data)] = [
            ("0x00010203", Data([0x00, 0x01, 0x02, 0x03])),
            ("0xabcdef", Data([0xAB, 0xCD, 0xEF])),
            ("0xFFFF", Data([0xFF, 0xFF]))
        ]

        for (hexString, expectedData) in testCases {
            let decoded = Data(hexString: hexString)
            #expect(decoded == expectedData)
        }
    }

    @Test("Hex decoding mixed case")
    func hexDecodingMixedCase() {
        let hexString = "aBcDeF012345"
        let decoded = Data(hexString: hexString)
        let expected = Data([0xAB, 0xCD, 0xEF, 0x01, 0x23, 0x45])
        #expect(decoded == expected)
    }

    // MARK: - Round-Trip Tests

    @Test("Hex round-trip conversion")
    func hexRoundTrip() {
        let testData = [
            Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05]),
            Data((0..<32).map { UInt8($0) }), // 32-byte inbox ID
            Data((0..<64).map { UInt8($0 % 256) }), // Larger data
            Data([0xFF, 0xAB, 0xCD, 0xEF]),
            Data()
        ]

        for original in testData {
            let hex = original.hexEncodedString()
            let roundTripped = Data(hexString: hex)
            #expect(roundTripped == original)
        }
    }

    @Test("Hex round-trip uppercase")
    func hexRoundTripUppercase() {
        let original = Data([0xAB, 0xCD, 0xEF, 0x12, 0x34])
        let hex = original.hexEncodedString(options: .upperCase)
        let roundTripped = Data(hexString: hex)
        #expect(roundTripped == original)
    }

    // MARK: - Edge Cases

    @Test("Hex decoding empty string")
    func hexDecodingEmptyString() {
        let decoded = Data(hexString: "")
        #expect(decoded == Data())
    }

    @Test("Hex decoding odd-length string returns nil")
    func hexDecodingOddLength() {
        let testCases = ["a", "abc", "12345", "0xabc"]

        for hexString in testCases {
            let decoded = Data(hexString: hexString)
            #expect(decoded == nil, "Odd-length hex string '\(hexString)' should return nil")
        }
    }

    @Test("Hex decoding invalid characters returns nil")
    func hexDecodingInvalidCharacters() {
        let testCases = [
            "abcdefg", // g is invalid
            "12 34", // space
            "zz",
            "GG",
            "hello world",
            "!@#$",
            "a-b-c-d"
        ]

        for hexString in testCases {
            let decoded = Data(hexString: hexString)
            #expect(decoded == nil, "Hex string with invalid chars '\(hexString)' should return nil")
        }
    }

    @Test("Hex decoding just 0x prefix returns empty data")
    func hexDecodingJustPrefix() {
        let decoded = Data(hexString: "0x")
        // "0x" with nothing after it -> empty string after stripping -> empty Data
        #expect(decoded == Data())
    }

    // MARK: - Inbox ID Specific Tests

    @Test("32-byte inbox ID conversion")
    func inboxIdConversion() {
        // Create a valid 32-byte inbox ID
        var inboxIdBytes = Data()
        for i in 0..<32 {
            inboxIdBytes.append(UInt8(i * 8 % 256))
        }

        let hexString = inboxIdBytes.hexEncodedString()
        #expect(hexString.count == 64)

        let decoded = Data(hexString: hexString)
        #expect(decoded == inboxIdBytes)
        #expect(decoded?.count == 32)
    }

    @Test("Invalid inbox ID length detection")
    func invalidInboxIdLength() {
        // Inbox IDs should be 32 bytes (64 hex chars)
        let invalidLengths = [
            "00", // 1 byte
            String(repeating: "00", count: 16), // 16 bytes
            String(repeating: "00", count: 31), // 31 bytes
            String(repeating: "00", count: 33), // 33 bytes
            String(repeating: "00", count: 64) // 64 bytes
        ]

        for hexString in invalidLengths {
            let decoded = Data(hexString: hexString)
            #expect(decoded != nil) // Should decode successfully
            if let data = decoded {
                // But length should match what was encoded
                #expect(data.count != 32 || hexString.count == 64)
            }
        }
    }

    @Test("Real-world inbox ID format")
    func realWorldInboxId() {
        // Example of a real XMTP inbox ID format (64 hex chars)
        let inboxIdHex = "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2"

        let decoded = Data(hexString: inboxIdHex)
        #expect(decoded != nil)
        #expect(decoded?.count == 32)

        if let data = decoded {
            let reencoded = data.hexEncodedString()
            #expect(reencoded == inboxIdHex)
        }
    }

    // MARK: - Performance Edge Cases

    @Test("Large data hex encoding")
    func largeDataHexEncoding() {
        // Test with larger data (1000 bytes)
        let largeData = Data((0..<1000).map { UInt8($0 % 256) })
        let hex = largeData.hexEncodedString()

        #expect(hex.count == 2000) // 2 hex chars per byte

        let decoded = Data(hexString: hex)
        #expect(decoded == largeData)
    }

    @Test("All byte values encode correctly")
    func allByteValuesEncode() {
        // Test all possible byte values (0-255)
        let allBytes = Data((0...255).map { UInt8($0) })
        let hex = allBytes.hexEncodedString()

        #expect(hex.count == 512) // 256 bytes × 2 hex chars

        let decoded = Data(hexString: hex)
        #expect(decoded == allBytes)
    }

    @Test("Whitespace in hex string returns nil")
    func whitespaceInHexString() {
        let testCases = [
            " abcd",
            "abcd ",
            "ab cd",
            "ab\ncd",
            "ab\tcd"
        ]

        for hexString in testCases {
            let decoded = Data(hexString: hexString)
            #expect(decoded == nil, "Hex string with whitespace should return nil")
        }
    }

    @Test("Hex string with special characters returns nil")
    func specialCharactersInHexString() {
        let testCases = [
            "ab-cd",
            "ab:cd",
            "ab cd",
            "ab_cd",
            "ab.cd"
        ]

        for hexString in testCases {
            let decoded = Data(hexString: hexString)
            #expect(decoded == nil)
        }
    }

    // MARK: - Consistency Between Encoding Methods

    @Test("Both encoding methods produce same result")
    func encodingMethodConsistency() {
        let testData = Data([0xAB, 0xCD, 0xEF, 0x12, 0x34, 0x56])

        let method1 = testData.hexEncodedString()
        let method2 = testData.toHex

        #expect(method1 == method2)
    }

    @Test("Case sensitivity in decoding")
    func caseSensitivityInDecoding() {
        let lowercase = "abcdef"
        let uppercase = "ABCDEF"
        let mixed = "AbCdEf"

        let decodedLower = Data(hexString: lowercase)
        let decodedUpper = Data(hexString: uppercase)
        let decodedMixed = Data(hexString: mixed)

        #expect(decodedLower == decodedUpper)
        #expect(decodedLower == decodedMixed)
        #expect(decodedUpper == decodedMixed)
    }
}

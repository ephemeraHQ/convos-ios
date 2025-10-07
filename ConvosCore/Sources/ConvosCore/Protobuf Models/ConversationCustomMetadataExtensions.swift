import Compression
import Foundation
import SwiftProtobuf
import XMTPiOS

// MARK: - Errors

enum ConversationCustomMetadataError: Error, LocalizedError {
    case randomGenerationFailed
    case invalidLength(Int)

    var errorDescription: String? {
        switch self {
        case .randomGenerationFailed:
            return "Failed to generate secure random bytes"
        case .invalidLength(let length):
            return "Invalid length for random string generation: \(length). Length must be positive."
        }
    }
}

// MARK: - DB Models

extension MemberProfile {
    var conversationProfile: ConversationProfile {
        .init(inboxId: inboxId, name: name, imageUrl: avatar)
    }
}

// MARK: - XMTP Extensions

extension XMTPiOS.Group {
    private var currentCustomMetadata: ConversationCustomMetadata {
        get throws {
            let currentDescription = try self.description()
            return ConversationCustomMetadata.parseDescriptionField(currentDescription)
        }
    }

    public var inviteTag: String {
        get throws {
            try currentCustomMetadata.tag
        }
    }

    // This should only be done by the conversation creator
    // Updating the invite tag effectively expires all invites generated with that tag
    // The tag is used by the invitee to verify the conversation they've been added to
    // is the one that corresponds to the invite they are requesting to join
    public func updateInviteTag() async throws {
        var customMetadata = try currentCustomMetadata
        customMetadata.tag = try generateSecureRandomString(length: 10)
        try await updateDescription(description: customMetadata.toCompactString())
    }

    /// Generates a cryptographically secure random string of specified length
    /// using alphanumeric characters (a-z, A-Z, 0-9)
    private func generateSecureRandomString(length: Int) throws -> String {
        // Validate that length is positive
        guard length > 0 else {
            throw ConversationCustomMetadataError.invalidLength(length)
        }

        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        let charactersArray = Array(characters)
        let charactersCount = charactersArray.count

        var randomBytes = [UInt8](repeating: 0, count: length)
        let result = SecRandomCopyBytes(kSecRandomDefault, length, &randomBytes)

        guard result == errSecSuccess else {
            throw ConversationCustomMetadataError.randomGenerationFailed
        }

        let randomString = randomBytes.map { byte in
            // Use modulo to map random byte to character index
            // This gives a slight bias but is acceptable for non-cryptographic identifiers
            let index = Int(byte) % charactersCount
            return charactersArray[index]
        }

        return String(randomString)
    }

    public var customDescription: String {
        get throws {
            try currentCustomMetadata.description_p
        }
    }

    public func updateCustomDescription(description: String) async throws {
        var customMetadata = try currentCustomMetadata
        customMetadata.description_p = description
        try await updateDescription(description: customMetadata.toCompactString())
    }

    public var memberProfiles: [MemberProfile] {
        get throws {
            let customMetadata = try currentCustomMetadata
            return customMetadata.profiles.map {
                .init(
                    conversationId: id,
                    inboxId: $0.inboxID,
                    name: $0.name,
                    avatar: $0.image
                )
            }
        }
    }

    public func updateProfile(_ profile: MemberProfile) async throws {
        var customMetadata = try currentCustomMetadata
        customMetadata.upsertProfile(profile.conversationProfile)
        try await updateDescription(description: customMetadata.toCompactString())
    }
}

// MARK: - Serialization Extensions

extension ConversationCustomMetadata {
    /// Magic byte to identify compressed vs uncompressed data
    internal static let compressionMarker: UInt8 = 0x1F  // GZIP-like marker
    private static let uncompressedMarker: UInt8 = 0x0A  // Common protobuf first byte

    /// Maximum allowed decompressed size (10 MB) to prevent decompression bombs
    private static let maxDecompressedSize: UInt32 = 10 * 1024 * 1024

    /// Serialize the metadata to the most compact string representation possible
    /// - Returns: Base64URL-encoded string (with optional compression for larger data)
    public func toCompactString() throws -> String {
        let protobufData = try self.serializedData()

        // For small data (< 100 bytes), compression usually makes it larger
        // For larger data (multiple profiles), compression can save significant space
        let data: Data
        if protobufData.count > 100 {
            // Try compression
            if let compressed = protobufData.compressedWithSize() {
                // Only use compression if it actually saves space (including size overhead)
                if compressed.count < protobufData.count {
                    data = compressed
                } else {
                    data = protobufData
                }
            } else {
                data = protobufData
            }
        } else {
            data = protobufData
        }

        return data.base64URLEncoded()
    }

    /// Deserialize metadata from a Base64URL-encoded string
    /// - Parameter string: Base64URL-encoded string containing the protobuf data
    /// - Returns: Decoded ConversationCustomMetadata instance
    public static func fromCompactString(_ string: String) throws -> ConversationCustomMetadata {
        let data = try string.base64URLDecoded()

        // Check if data is compressed by looking at the first byte
        let protobufData: Data
        if data.first == compressionMarker {
            // Data format: [marker: 1 byte][size: 4 bytes][compressed data]
            guard let decompressed = data.decompressedWithSize(maxSize: maxDecompressedSize) else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(codingPath: [], debugDescription: "Failed to decompress metadata")
                )
            }
            protobufData = decompressed
        } else {
            protobufData = data
        }

        return try ConversationCustomMetadata(serializedBytes: protobufData)
    }

    /// Check if a string appears to be encoded metadata (vs plain text description)
    /// - Parameter string: The string to check
    /// - Returns: true if the string appears to be Base64URL-encoded metadata
    public static func isEncodedMetadata(_ string: String) -> Bool {
        // Quick heuristics to detect if this is likely our encoded metadata:
        // 1. Must be non-empty
        // 2. Should only contain Base64URL characters
        // 3. Try to decode and parse (more expensive, so do last)

        guard !string.isEmpty else { return false }

        // Base64URL character set: A-Z, a-z, 0-9, -, _
        let base64URLCharSet = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        guard string.rangeOfCharacter(from: base64URLCharSet.inverted) == nil else {
            return false
        }

        // Try to actually decode it
        do {
            _ = try ConversationCustomMetadata.fromCompactString(string)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Convenience Initializers

extension ConversationCustomMetadata {
    /// Create metadata with just a description
    public init(description: String) {
        self.init()
        self.description_p = description
    }

    /// Create metadata with description and profiles
    public init(description: String, profiles: [ConversationProfile]) {
        self.init()
        self.description_p = description
        self.profiles = profiles
    }
}

extension ConversationProfile {
    /// Convenience initializer
    public init(inboxId: String, name: String? = nil, imageUrl: String? = nil) {
        self.init()
        self.inboxID = inboxId
        if let name = name {
            self.name = name
        }
        if let imageUrl = imageUrl {
            self.image = imageUrl
        }
    }
}

// MARK: - Helper Methods for Managing Metadata

extension ConversationCustomMetadata {
    /// Add or update a profile in the metadata
    /// - Parameter profile: The profile to add or update (matched by inboxId)
    public mutating func upsertProfile(_ profile: ConversationProfile) {
        if let index = profiles.firstIndex(where: { $0.inboxID == profile.inboxID }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
    }

    /// Remove a profile by inbox ID
    /// - Parameter inboxId: The inbox ID of the profile to remove
    /// - Returns: true if a profile was removed
    @discardableResult
    public mutating func removeProfile(inboxId: String) -> Bool {
        if let index = profiles.firstIndex(where: { $0.inboxID == inboxId }) {
            profiles.remove(at: index)
            return true
        }
        return false
    }

    /// Find a profile by inbox ID
    /// - Parameter inboxId: The inbox ID to search for
    /// - Returns: The profile if found, nil otherwise
    public func findProfile(inboxId: String) -> ConversationProfile? {
        return profiles.first { $0.inboxID == inboxId }
    }
}

// MARK: - Migration Support

extension ConversationCustomMetadata {
    /// Parse a description field that might be either plain text or encoded metadata
    /// - Parameter descriptionField: The raw description field from XMTP
    /// - Returns: ConversationCustomMetadata with either decoded data or plain text description
    public static func parseDescriptionField(_ descriptionField: String?) -> ConversationCustomMetadata {
        guard let descriptionField = descriptionField, !descriptionField.isEmpty else {
            return ConversationCustomMetadata()
        }

        // Try to decode as metadata first
        if let metadata = try? ConversationCustomMetadata.fromCompactString(descriptionField) {
            return metadata
        }

        // Fall back to treating it as plain text description
        return ConversationCustomMetadata(description: descriptionField)
    }
}

// MARK: - Compression Helpers

private extension Data {
    /// Compress data using zlib deflate and prepend format metadata
    /// Format: [marker: 1 byte][original size: 4 bytes big-endian][compressed data]
    func compressedWithSize() -> Data? {
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

            // Build the final data: [marker][size][compressed]
            var result = Data()
            result.append(ConversationCustomMetadata.compressionMarker)

            // Store original size as UInt32 big-endian (4 bytes)
            var sizeBytes = UInt32(count).bigEndian
            result.append(Data(bytes: &sizeBytes, count: 4))

            // Append compressed data
            result.append(Data(bytes: destinationBuffer, count: compressedSize))

            return result
        }
    }

    /// Decompress data using zlib inflate with size metadata
    /// Expected format: [marker: 1 byte][original size: 4 bytes big-endian][compressed data]
    /// - Parameter maxSize: Maximum allowed decompressed size (safety limit)
    /// - Returns: Decompressed data or nil if decompression fails or exceeds maxSize
    func decompressedWithSize(maxSize: UInt32) -> Data? {
        // Expected format: [marker][size: 4 bytes][compressed data]
        // Minimum: 1 (marker) + 4 (size) + 1 (data) = 6 bytes
        guard count >= 6 else { return nil }

        // Skip marker byte (already checked by caller)
        let dataAfterMarker = self.dropFirst()

        // Read original size (4 bytes, big-endian)
        guard dataAfterMarker.count >= 4 else { return nil }
        let sizeBytes = dataAfterMarker.prefix(4)
        let originalSize: UInt32 = sizeBytes.withUnsafeBytes { ptr in
            // Directly load the 4 bytes as UInt32 and convert from big-endian
            let raw = ptr.load(as: UInt32.self)
            return UInt32(bigEndian: raw)
        }
        // Security check: reject if original size exceeds maximum
        guard originalSize > 0, originalSize <= maxSize else { return nil }

        // Get compressed data (everything after size bytes)
        let compressedData = dataAfterMarker.dropFirst(4)
        guard !compressedData.isEmpty else { return nil }

        // Decompress with exact buffer size
        return compressedData.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return nil }

            let sourceBuffer = UnsafeBufferPointer<UInt8>(
                start: baseAddress.assumingMemoryBound(to: UInt8.self),
                count: compressedData.count
            )

            guard let sourceBaseAddress = sourceBuffer.baseAddress else { return nil }

            // Allocate exactly the size we expect
            let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(originalSize))
            defer { destinationBuffer.deallocate() }

            let decompressedSize = compression_decode_buffer(
                destinationBuffer, Int(originalSize),
                sourceBaseAddress, compressedData.count,
                nil, COMPRESSION_ZLIB
            )

            // Verify decompression succeeded and matches expected size
            guard decompressedSize > 0, decompressedSize == Int(originalSize) else {
                return nil
            }

            return Data(bytes: destinationBuffer, count: decompressedSize)
        }
    }
}

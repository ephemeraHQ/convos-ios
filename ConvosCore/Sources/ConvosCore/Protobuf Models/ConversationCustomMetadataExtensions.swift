import Foundation
import SwiftProtobuf
import XMTPiOS

// swiftlint:disable:next orphaned_doc_comment
/// XMTP groups have a limited description field that Convos uses to store structured
/// metadata as a compressed, base64-encoded protobuf. This metadata includes:
/// - Invite tag: Unique identifier linking invites to conversations
/// - Description: User-visible conversation description
/// - Expiration date: Optional timestamp when conversation auto-deletes
/// - Member profiles: Name and avatar URL for each member (per-conversation identities)
///
/// **Compression Strategy:**
/// - Small metadata (<100 bytes): Stored as uncompressed protobuf + base64
/// - Large metadata (multiple profiles): Compressed with zlib if beneficial
/// - Format: [marker byte][size][data] for safe decompression with size limits
///
/// **Migration Support:**
/// - Gracefully handles plain text descriptions from older versions
/// - `parseDescriptionField()` auto-detects format and migrates seamlessly
///
/// This allows Convos to store rich conversation metadata without requiring a backend.

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

    public var expiresAt: Date? {
        get throws {
            let metadata = try currentCustomMetadata
            guard metadata.hasExpiresAt else { return nil }
            return metadata.expiresAt.date
        }
    }

    public func updateExpiresAt(date: Date) async throws {
        var customMetadata = try currentCustomMetadata
        customMetadata.expiresAt = .init(date: date)
        try await updateDescription(description: customMetadata.toCompactString())
    }

    // This should only be done by the conversation creator
    // Updating the invite tag effectively expires all invites generated with that tag
    // The tag is used by the invitee to verify the conversation they've been added to
    // is the one that corresponds to the invite they are requesting to join
    public func ensureInviteTag() async throws {
        var customMetadata = try currentCustomMetadata
        guard customMetadata.tag.isEmpty else { return }
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
                    name: $0.hasName ? $0.name : nil,
                    avatar: $0.hasImage ? $0.image : nil
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
    /// Maximum allowed decompressed size to prevent decompression bombs
    private static let maxDecompressedSize: UInt32 = 10 * 1024 * 1024

    /// Minimum size threshold for compression - compression overhead makes it counterproductive below this size
    private static let compressionThreshold: Int = 100

    /// Serialize the metadata to the most compact string representation possible
    /// - Returns: Base64URL-encoded string with optional compression
    public func toCompactString() throws -> String {
        let protobufData = try self.serializedData()

        // For small data, compression usually makes it larger
        let data: Data
        if protobufData.count > Self.compressionThreshold, let compressed = protobufData.compressedIfSmaller() {
            data = compressed
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

        let protobufData: Data
        // validate compression marker value explicitly
        if let firstByte = data.first, firstByte == Data.compressionMarker {
            let dataWithoutMarker = data.dropFirst()
            guard let decompressed = dataWithoutMarker.decompressedWithSize(maxSize: maxDecompressedSize) else {
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
        } else {
            self.clearName()
        }
        if let imageUrl = imageUrl {
            self.image = imageUrl
        } else {
            self.clearImage()
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

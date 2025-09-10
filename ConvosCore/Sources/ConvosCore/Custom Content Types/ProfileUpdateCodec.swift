import Foundation
import XMTPiOS

public struct ProfileUpdate: Codable {
    public let displayName: String?
    public let avatar: String?
}

public let ContentTypeProfileUpdate = ContentTypeID(authorityID: "convos.org", typeID: "profile_update", versionMajor: 1, versionMinor: 0)

public enum ProfileUpdateCodecError: Error, LocalizedError {
    case emptyContent
    case invalidJSONFormat

    public var errorDescription: String? {
        switch self {
        case .emptyContent:
            return "ProfileUpdate content is empty"
        case .invalidJSONFormat:
            return "Invalid JSON format for ProfileUpdate"
        }
    }
}

public struct ProfileUpdateCodec: ContentCodec {
    public typealias T = ProfileUpdate

    public var contentType: ContentTypeID = ContentTypeProfileUpdate

    public func encode(content: ProfileUpdate) throws -> EncodedContent {
        var encodedContent = EncodedContent()
        encodedContent.type = ContentTypeProfileUpdate

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encodedContent.content = try encoder.encode(content)

        return encodedContent
    }

    public func decode(content: EncodedContent) throws -> ProfileUpdate {
        guard !content.content.isEmpty else {
            throw ProfileUpdateCodecError.emptyContent
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            return try decoder.decode(ProfileUpdate.self, from: content.content)
        } catch {
            throw ProfileUpdateCodecError.invalidJSONFormat
        }
    }

    public func fallback(content: ProfileUpdate) throws -> String? {
        return "Profile updated name: \(content.displayName ?? "nil"), avatar: \(content.avatar ?? "nil")"
    }

    public func shouldPush(content: ProfileUpdate) throws -> Bool {
        true
    }
}

import Foundation
import GRDB
import XMTPiOS

extension XMTPiOS.DecodedMessage {
    enum DecodedMessageDBRepresentationError: Error {
        case mismatchedContentType, unsupportedContentType
    }

    func dbRepresentation() throws -> DBMessage {
        let status: MessageStatus = deliveryStatus.status
        let content = try content() as Any
        let encodedContentType = try encodedContent.type
        let messageType: DBMessageType
        let contentType: MessageContentType
        let sourceMessageId: String?
        let emoji: String?
        let attachmentUrls: [String]
        let text: String?

        switch encodedContentType {
        case ContentTypeText:
            guard let contentString = content as? String else {
                throw DecodedMessageDBRepresentationError.mismatchedContentType
            }
            text = contentString
            messageType = .original
            contentType = .text
            attachmentUrls = []
            emoji = nil
            sourceMessageId = nil
        case ContentTypeReply:
            guard let contentReply = content as? Reply else {
                throw DecodedMessageDBRepresentationError.mismatchedContentType
            }
            sourceMessageId = contentReply.reference
            messageType = .reply
            emoji = nil

            switch contentReply.contentType {
            case ContentTypeText:
                guard let contentString = contentReply.content as? String else {
                    throw DecodedMessageDBRepresentationError.mismatchedContentType
                }
                text = contentString
                contentType = .text
                attachmentUrls = []
            case ContentTypeRemoteAttachment:
                guard let remoteAttachment = content as? RemoteAttachment else {
                    throw DecodedMessageDBRepresentationError.mismatchedContentType
//                      let encodedContent: EncodedContent = try? await remoteAttachment.content(),
//                      let attachment: Attachment = try? encodedContent.decoded(),
//                      let localURL = try? attachment.saveToTmpFile() else {
                }
                attachmentUrls = [remoteAttachment.url]
                contentType = .attachments
                text = nil
            default:
                Logger.error("Unhandled contentType \(contentReply.contentType)")
                contentType = .text
                text = nil
                attachmentUrls = []
            }
        case ContentTypeReaction, ContentTypeReactionV2:
            guard let reaction = content as? Reaction else {
                throw DecodedMessageDBRepresentationError.mismatchedContentType
            }
            sourceMessageId = reaction.reference
            messageType = .reaction
            emoji = reaction.emoji
            contentType = .emoji
            text = nil
            attachmentUrls = []
        case ContentTypeMultiRemoteAttachment:
            guard let remoteAttachments = content as? [RemoteAttachment] else {
                throw DecodedMessageDBRepresentationError.mismatchedContentType
            }
            messageType = .original
            attachmentUrls = remoteAttachments.map { $0.url }
            contentType = .attachments
            text = nil
            emoji = nil
            sourceMessageId = nil
        case ContentTypeRemoteAttachment:
            guard let remoteAttachment = content as? RemoteAttachment else {
                throw DecodedMessageDBRepresentationError.mismatchedContentType
            }
            messageType = .original
            attachmentUrls = [remoteAttachment.url]
            contentType = .attachments
            text = nil
            emoji = nil
            sourceMessageId = nil
        case ContentTypeGroupUpdated:
            guard let groupUpdated = content as? GroupUpdated else {
                throw DecodedMessageDBRepresentationError.mismatchedContentType
            }
            messageType = .original
            attachmentUrls = []
            contentType = .update
            text = ""
            emoji = nil
            sourceMessageId = nil
        case ContentTypeAttachment:
            throw DecodedMessageDBRepresentationError.unsupportedContentType
        default:
            throw DecodedMessageDBRepresentationError.unsupportedContentType
        }

        return .init(
            id: id,
            clientMessageId: id,
            conversationId: conversationId,
            senderId: senderInboxId,
            date: sentAt,
            status: status,
            messageType: messageType,
            contentType: contentType,
            text: text,
            emoji: emoji,
            sourceMessageId: sourceMessageId,
            attachmentUrls: attachmentUrls
        )
    }
}

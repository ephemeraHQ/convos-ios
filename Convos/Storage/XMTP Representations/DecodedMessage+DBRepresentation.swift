import Foundation
import GRDB
import XMTPiOS

extension XMTPiOS.DecodedMessage {
    enum DecodedMessageDBRepresentationError: Error {
        case mismatchedContentType, unsupportedContentType
    }

    func dbRepresentation(conversationId: String,
                          sender: Profile) throws -> any MessageType {
        let source: MessageSource = sender.isCurrentUser ? .outgoing : .incoming
        let status: MessageStatus = deliveryStatus.status

        let content = try content() as Any
        let encodedContentType = try encodedContent.type
        switch encodedContentType {
        case ContentTypeText:
            guard let contentString = content as? String else {
                throw DecodedMessageDBRepresentationError.mismatchedContentType
            }
            let kind: MessageKind = .text(contentString)
            return Message(id: id,
                           conversationId: conversationId,
                           sender: sender,
                           date: sentAt,
                           kind: kind,
                           source: source,
                           status: status)
        case ContentTypeReply:
            guard let contentReply = content as? Reply else {
                throw DecodedMessageDBRepresentationError.mismatchedContentType
            }
            let sourceMessageId = contentReply.reference
            let kind: MessageKind
            switch contentReply.contentType {
            case ContentTypeText:
                guard let contentString = contentReply.content as? String else {
                    throw DecodedMessageDBRepresentationError.mismatchedContentType
                }
                kind = .text(contentString)
            case ContentTypeRemoteAttachment:
                guard let remoteAttachment = content as? RemoteAttachment else {
                    throw DecodedMessageDBRepresentationError.mismatchedContentType
                    //                      let encodedContent: EncodedContent = try? await remoteAttachment.content(),
                    //                      let attachment: Attachment = try? encodedContent.decoded(),
                    //                      let localURL = try? attachment.saveToTmpFile() else {
                }
                kind = .attachment(URL(string: "http://google.com")!)
            default:
                Logger.error("Unhandled contentType \(contentReply.contentType)")
                kind = .text("")
            }
            return MessageReply(id: id,
                                conversationId: conversationId,
                                sender: sender,
                                date: sentAt,
                                kind: kind,
                                source: source,
                                status: status,
                                sourceMessageId: sourceMessageId)
        case ContentTypeReaction, ContentTypeReactionV2:
            guard let reaction = content as? Reaction else {
                throw DecodedMessageDBRepresentationError.mismatchedContentType
            }
            return MessageReaction(id: id,
                                   conversationId: conversationId,
                                   sender: sender,
                                   date: sentAt,
                                   source: source,
                                   status: status,
                                   sourceMessageId: reaction.reference,
                                   emoji: reaction.emoji)
        case ContentTypeRemoteAttachment:
            guard let remoteAttachment = content as? RemoteAttachment else {
                throw DecodedMessageDBRepresentationError.mismatchedContentType
            }
            return Message(id: id,
                           conversationId: conversationId,
                           sender: sender,
                           date: sentAt,
                           kind: .attachment(URL(string: "http://google.com")!),
                           source: source,
                           status: status)
        case ContentTypeAttachment:
            throw DecodedMessageDBRepresentationError.unsupportedContentType
        default:
            throw DecodedMessageDBRepresentationError.unsupportedContentType
        }
    }
}

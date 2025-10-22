import Foundation
import GRDB
import XMTPiOS

extension XMTPiOS.DecodedMessage {
    enum DecodedMessageDBRepresentationError: Error {
        case mismatchedContentType, unsupportedContentType
    }

    private struct DBMessageComponents {
        var messageType: DBMessageType
        var contentType: MessageContentType
        var sourceMessageId: String?
        var emoji: String?
        var attachmentUrls: [String]
        var text: String?
        var update: DBMessage.Update?
    }

    func dbRepresentation() throws -> DBMessage {
        let status: MessageStatus = deliveryStatus.status
        let encodedContentType = try encodedContent.type
        let components: DBMessageComponents

        switch encodedContentType {
        case ContentTypeText:
            components = try handleTextContent()
        case ContentTypeReply:
            components = try handleReplyContent()
        case ContentTypeReaction, ContentTypeReactionV2:
            components = try handleReactionContent()
        case ContentTypeMultiRemoteAttachment:
            components = try handleMultiRemoteAttachmentContent()
        case ContentTypeRemoteAttachment:
            components = try handleRemoteAttachmentContent()
        case ContentTypeGroupUpdated:
            components = try handleGroupUpdatedContent()
        case ContentTypeExplodeSettings:
            components = try handleExplodeSettingsContent()
        default:
            throw DecodedMessageDBRepresentationError.unsupportedContentType
        }

        return .init(
            id: id,
            clientMessageId: id,
            conversationId: conversationId,
            senderId: senderInboxId,
            dateNs: sentAtNs,
            date: sentAt,
            status: status,
            messageType: components.messageType,
            contentType: components.contentType,
            text: components.text,
            emoji: components.emoji,
            sourceMessageId: components.sourceMessageId,
            attachmentUrls: components.attachmentUrls,
            update: components.update
        )
    }

    private func handleTextContent() throws -> DBMessageComponents {
        let content = try content() as Any
        guard let contentString = content as? String else {
            throw DecodedMessageDBRepresentationError.mismatchedContentType
        }
        return DBMessageComponents(
            messageType: .original,
            contentType: .text,
            sourceMessageId: nil,
            emoji: nil,
            attachmentUrls: [],
            text: contentString,
            update: nil
        )
    }

    private func handleReplyContent() throws -> DBMessageComponents {
        let content = try content() as Any
        guard let contentReply = content as? Reply else {
            throw DecodedMessageDBRepresentationError.mismatchedContentType
        }
        let sourceMessageId = contentReply.reference
        switch contentReply.contentType {
        case ContentTypeText:
            guard let contentString = contentReply.content as? String else {
                throw DecodedMessageDBRepresentationError.mismatchedContentType
            }
            return DBMessageComponents(
                messageType: .reply,
                contentType: .text,
                sourceMessageId: sourceMessageId,
                emoji: nil,
                attachmentUrls: [],
                text: contentString,
                update: nil
            )
        case ContentTypeRemoteAttachment:
            guard let remoteAttachment = content as? RemoteAttachment else {
                throw DecodedMessageDBRepresentationError.mismatchedContentType
            }
            return DBMessageComponents(
                messageType: .reply,
                contentType: .attachments,
                sourceMessageId: sourceMessageId,
                emoji: nil,
                attachmentUrls: [remoteAttachment.url],
                text: nil,
                update: nil
            )
        default:
            Logger.error("Unhandled contentType \(contentReply.contentType)")
            return DBMessageComponents(
                messageType: .reply,
                contentType: .text,
                sourceMessageId: sourceMessageId,
                emoji: nil,
                attachmentUrls: [],
                text: nil,
                update: nil
            )
        }
    }

    private func handleReactionContent() throws -> DBMessageComponents {
        let content = try content() as Any
        guard let reaction = content as? Reaction else {
            throw DecodedMessageDBRepresentationError.mismatchedContentType
        }
        return DBMessageComponents(
            messageType: .reaction,
            contentType: .emoji,
            sourceMessageId: reaction.reference,
            emoji: reaction.emoji,
            attachmentUrls: [],
            text: nil,
            update: nil
        )
    }

    private func handleMultiRemoteAttachmentContent() throws -> DBMessageComponents {
        let content = try content() as Any
        guard let remoteAttachments = content as? [RemoteAttachment] else {
            throw DecodedMessageDBRepresentationError.mismatchedContentType
        }
        return DBMessageComponents(
            messageType: .original,
            contentType: .attachments,
            sourceMessageId: nil,
            emoji: nil,
            attachmentUrls: remoteAttachments.map { $0.url },
            text: nil,
            update: nil
        )
    }

    private func handleRemoteAttachmentContent() throws -> DBMessageComponents {
        let content = try content() as Any
        guard let remoteAttachment = content as? RemoteAttachment else {
            throw DecodedMessageDBRepresentationError.mismatchedContentType
        }
        return DBMessageComponents(
            messageType: .original,
            contentType: .attachments,
            sourceMessageId: nil,
            emoji: nil,
            attachmentUrls: [remoteAttachment.url],
            text: nil,
            update: nil
        )
    }

    private func handleGroupUpdatedContent() throws -> DBMessageComponents {
        let content = try content() as Any
        guard let groupUpdated = content as? GroupUpdated else {
            throw DecodedMessageDBRepresentationError.mismatchedContentType
        }
        let metadataFieldChanges: [DBMessage.Update.MetadataChange] = try groupUpdated.metadataFieldChanges
            .map {
                if $0.fieldName == ConversationUpdate.MetadataChange.Field.description.rawValue {
                    let oldCustomValue = $0.hasOldValue ? try ConversationCustomMetadata.fromCompactString($0.oldValue) : nil
                    let newCustomValue = $0.hasNewValue ? try ConversationCustomMetadata.fromCompactString($0.newValue) : nil
                    if let old = oldCustomValue, let new = newCustomValue, old.description_p == new.description_p {
                        if old.expiresAt != new.expiresAt {
                            return .init(
                                field: ConversationUpdate.MetadataChange.Field.expiresAt.rawValue,
                                oldValue: old.expiresAt.date.ISO8601Format(),
                                newValue: new.expiresAt.date.ISO8601Format()
                            )
                        }
                        return .init(
                            field: ConversationUpdate.MetadataChange.Field.custom.rawValue,
                            oldValue: nil,
                            newValue: nil
                        )
                    } else {
                        return .init(
                            field: ConversationUpdate.MetadataChange.Field.description.rawValue,
                            oldValue: $0.hasOldValue ? oldCustomValue?.description_p : nil,
                            newValue: $0.hasNewValue ? newCustomValue?.description_p : nil
                        )
                    }
                } else {
                    return .init(
                        field: $0.fieldName,
                        oldValue: $0.hasOldValue ? $0.oldValue : nil,
                        newValue: $0.hasNewValue ? $0.newValue : nil
                    )
                }
            }
        let update = DBMessage.Update(
            initiatedByInboxId: groupUpdated.initiatedByInboxID,
            addedInboxIds: groupUpdated.addedInboxes.map { $0.inboxID },
            removedInboxIds: groupUpdated.removedInboxes.map { $0.inboxID },
            metadataChanges: metadataFieldChanges,
            expiresAt: nil
        )
        return DBMessageComponents(
            messageType: .original,
            contentType: .update,
            sourceMessageId: nil,
            emoji: nil,
            attachmentUrls: [],
            text: nil,
            update: update
        )
    }

    private func handleExplodeSettingsContent() throws -> DBMessageComponents {
        let content = try content() as Any
        guard let explodeSettings = content as? ExplodeSettings else {
            throw DecodedMessageDBRepresentationError.mismatchedContentType
        }

        Logger.info("Received explode settings: \(explodeSettings)")
        let update = DBMessage.Update(
            initiatedByInboxId: senderInboxId,
            addedInboxIds: [],
            removedInboxIds: [],
            metadataChanges: [],
            expiresAt: explodeSettings.expiresAt
        )

        return DBMessageComponents(
            messageType: .original,
            contentType: .update,
            sourceMessageId: nil,
            emoji: nil,
            attachmentUrls: [],
            text: nil,
            update: update
        )
    }
}

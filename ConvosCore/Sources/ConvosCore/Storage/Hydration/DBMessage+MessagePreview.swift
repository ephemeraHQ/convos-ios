import Foundation

extension DBMessage {
    func hydrateMessagePreview(conversationKind: ConversationKind) -> MessagePreview {
        let text: String
        let senderString: String = "Sender "
        let optionalSender: String = conversationKind == .group ? senderString : ""
        let attachmentsCount = attachmentUrls.count
        let attachmentsString = attachmentsCount <= 1 ? "a photo" : "\(attachmentsCount) photos"

        switch messageType {
        case .original:
            switch contentType {
            case .attachments:
                text = "\(optionalSender)sent \(attachmentsString)".capitalized
            case .text, .emoji:
                text = self.text ?? ""
            case .update:
                text = ""
            }

        case .reply:
            let originalMessage: String = "original"
            switch contentType {
            case .attachments:
                text = "\(optionalSender)replied with \(attachmentsString)".capitalized
            case .text, .emoji:
                text = "\(optionalSender)replied: \(self.text ?? "") to \"\(originalMessage)\"".capitalized
            case .update:
                text = ""
            }

        case .reaction:
            let originalMessage: String = "original"
            switch contentType {
            case .attachments:
                text = "\(optionalSender)sent \(attachmentsString)".capitalized
            case .text, .emoji:
                text = "\(senderString)\(emoji ?? "")'d \(originalMessage)".capitalized
            case .update:
                text = ""
            }
        }
        return .init(text: text, createdAt: date)
    }
}

import Foundation

extension DBMessage {
    func hydrateMessagePreview() -> MessagePreview {
        let text: String
        let sender: String = "Sender"
        let attachmentsCount = attachmentUrls.count
        let attachmentsString = attachmentsCount <= 1 ? "a photo" : "\(attachmentsCount) photos"

        switch messageType {
        case .original:
            switch contentType {
            case .attachments:
                text = "\(sender) sent \(attachmentsString)"
            case .text, .emoji:
                text = self.text ?? ""
            }

        case .reply:
            let originalMessage: String = "original"
            switch contentType {
            case .attachments:
                text = "\(sender) replied with \(attachmentsString)"
            case .text, .emoji:
                text = "\(sender) replied: \(self.text ?? "") to \"\(originalMessage)\""
            }

        case .reaction:
            let originalMessage: String = "original"
            switch contentType {
            case .attachments:
                let count = attachmentUrls.count
                text = "\(sender) sent \(attachmentsString)"
            case .text, .emoji:
                text = "\(sender) \(emoji ?? "")'d \(originalMessage)"
            }

        }
        return .init(text: text, createdAt: date)
    }
}

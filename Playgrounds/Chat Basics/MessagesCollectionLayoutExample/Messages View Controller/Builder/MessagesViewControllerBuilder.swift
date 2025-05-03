import Foundation
import UIKit

struct MessagesViewControllerBuilder {
    @MainActor
    static func build() -> MessagesViewController {
        let currentUser = User(id: 0, name: "You")
        let messagesProvider = MockMessagesProvider(currentUser: currentUser)
        let messageController = MockMessagingService(dataProvider: messagesProvider, userId: currentUser.id)
        let dataSource = MockMessagesCollectionDataSource()
        messagesProvider.delegate = messageController
        let messageViewController = MessagesViewController(messagingService: messageController,
                                                         dataSource: dataSource)
        messageController.delegate = messageViewController
        return messageViewController
    }
}

import Foundation
import UIKit

struct MessagesViewControllerBuilder {
    static func build(enableImages: Bool = true) -> MessagesViewController {
        let currentUser = User(id: 0, name: "You")
        let messagesProvider = MockMessagesProvider(currentUser: currentUser, enableImages: enableImages)
        let messageController = MockMessagingService(dataProvider: messagesProvider, userId: currentUser.id)
        let dataSource = MockMessagesCollectionDataSource()
        messagesProvider.delegate = messageController
        let messageViewController = MessagesViewController(messagingService: messageController,
                                                         dataSource: dataSource)
        messageController.delegate = messageViewController
        return messageViewController
    }
}

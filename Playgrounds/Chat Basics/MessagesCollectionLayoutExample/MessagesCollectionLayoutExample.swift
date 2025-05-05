import SwiftUI

@main
struct MessagesCollectionLayoutExample: App {
    let messagingService: MessagingServiceProtocol = MockMessagingService()

    var body: some Scene {
        WindowGroup {
            MessagesView(messagingService: messagingService)
                .navigationBarHidden(true)
                .ignoresSafeArea()
        }
    }
}

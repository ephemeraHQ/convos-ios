import SwiftUI

let messaging = MockMessagingService()
let conversationId: String = "1"
let dependencies = ConversationViewDependencies(
    conversationId: conversationId,
    conversationRepository: messaging.conversationRepository(for: conversationId),
    messagesRepository: messaging.messagesRepository(for: conversationId),
    outgoingMessageWriter: messaging.messageWriter(for: conversationId),
    conversationConsentWriter: messaging.conversationConsentWriter(),
    conversationLocalStateWriter: messaging.conversationLocalStateWriter(),
    groupMetadataWriter: messaging.groupMetadataWriter()
)

@main
struct ConvosApp: App {
    let convos: ConvosClient = .client(environment: .dev)
    let analyticsService: AnalyticsServiceProtocol = PosthogAnalyticsService.shared

    init() {
        SDKConfiguration.configureSDKs()
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                convos: convos,
                analyticsService: analyticsService
            )
        }
    }
}

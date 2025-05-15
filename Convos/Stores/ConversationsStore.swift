import Combine
import Foundation
import Observation

struct ConversationItem: Hashable, Identifiable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.id == rhs.id
    }

    let conversation: any ConvosSDK.ConversationType
    var id: String {
        conversation.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

@Observable
class ConversationsStore {
    private let messagingService: any ConvosSDK.MessagingServiceProtocol
    private var cancellables: Set<AnyCancellable> = []

    var conversations: [ConversationItem] = []
    var pinnedConversations: [ConversationItem] {
        conversations.filter { $0.conversation.isPinned }
    }
    var unpinnedConversations: [ConversationItem] {
        conversations.filter { !$0.conversation.isPinned }
    }

    init(messagingService: any ConvosSDK.MessagingServiceProtocol) {
        self.messagingService = messagingService
        self.messagingService.messagingStatePublisher()
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    Task { [weak self] in
                        guard let self else { return }
                        await reloadConversations()
                    }
                    startStreamingConversations()
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }

    private func startStreamingConversations() {
        Task {
            Logger.info("Starting conversations stream...")
            do {
                for try await conversation in await messagingService.conversationsStream() {
                    conversations.append(.init(conversation: conversation))
                }
            } catch {
                Logger.error("Error streaming conversations: \(error)")
            }
        }
    }

    private func reloadConversations() async {
        Logger.info("Reloading conversations...")
        do {
            conversations = try await messagingService
                .conversations()
                .map { .init(conversation: $0) }
            Logger.info("Reloaded conversations: \(conversations)")
        } catch {
            Logger.error("Error reloading conversations: \(error)")
        }
    }
}

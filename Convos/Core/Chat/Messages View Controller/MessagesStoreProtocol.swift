import Combine
import Foundation

struct MessagingServiceUpdate {
    let sections: [MessagesCollectionSection]
    let requiresIsolatedProcess: Bool
}

@MainActor
protocol MessagesStoreProtocol {
    var updates: AnyPublisher<MessagingServiceUpdate, Never> { get }
    func loadInitialMessages() async -> [MessagesCollectionSection]
    func loadPreviousMessages() async -> [MessagesCollectionSection]
    func sendMessage(_ content: MessageContent) async -> [MessagesCollectionSection]
}

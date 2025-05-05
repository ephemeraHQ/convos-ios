import Combine
import Foundation

struct MessagingServiceUpdate {
    let sections: [Section]
    let requiresIsolatedProcess: Bool
}

@MainActor
protocol TempMessagingServiceProtocol {
    var updates: AnyPublisher<MessagingServiceUpdate, Never> { get }
    func loadInitialMessages() async -> [Section]
    func loadPreviousMessages() async -> [Section]
    func sendMessage(_ data: Message.Data) async -> [Section]
}

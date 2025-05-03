import Foundation

@MainActor
protocol MessagingServiceProtocol {
    func loadInitialMessages() async -> [Section]
    func loadPreviousMessages() async -> [Section]
    func sendMessage(_ data: Message.Data) async -> [Section]
}

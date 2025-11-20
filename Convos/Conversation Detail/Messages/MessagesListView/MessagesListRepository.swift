import Combine
import ConvosCore
import Foundation

/// A wrapper around MessagesRepository that transforms messages into display items for SwiftUI
@MainActor
protocol MessagesListRepositoryProtocol {
    var messagesListPublisher: AnyPublisher<[MessagesListItemType], Never> { get }
    var conversationMessagesListPublisher: AnyPublisher<(String, [MessagesListItemType]), Never> { get }

    func fetchAll() throws -> [MessagesListItemType]
}

@MainActor
final class MessagesListRepository: MessagesListRepositoryProtocol {
    // MARK: - Private Properties

    private let messagesRepository: any MessagesRepositoryProtocol
    private let messagesListSubject: CurrentValueSubject<[MessagesListItemType], Never> = .init([])
    private var cancellables: Set<AnyCancellable> = .init()

    // MARK: - Public Properties

    var messagesListPublisher: AnyPublisher<[MessagesListItemType], Never> {
        messagesListSubject.eraseToAnyPublisher()
    }

    var conversationMessagesListPublisher: AnyPublisher<(String, [MessagesListItemType]), Never> {
        messagesRepository.conversationMessagesPublisher
            .map { [weak self] conversationId, messages in
                let processedMessages = self?.processMessages(messages) ?? []
                return (conversationId, processedMessages)
            }
            .handleEvents(receiveOutput: { [weak self] _, processedMessages in
                self?.messagesListSubject.send(processedMessages)
            })
            .eraseToAnyPublisher()
    }

    // MARK: - Initialization

    init(messagesRepository: any MessagesRepositoryProtocol) {
        self.messagesRepository = messagesRepository

        // Subscribe to messages and transform them once when they change
        messagesRepository.messagesPublisher
            .map { [weak self] messages in
                self?.processMessages(messages) ?? []
            }
            .sink { [weak self] processedMessages in
                self?.messagesListSubject.send(processedMessages)
            }
            .store(in: &cancellables)
    }

    // MARK: - Public Methods

    func fetchAll() throws -> [MessagesListItemType] {
        let messages = try messagesRepository.fetchAll()
        return processMessages(messages)
    }

    // MARK: - Private Methods

    private func processMessages(_ messages: [AnyMessage]) -> [MessagesListItemType] {
        return MessagesListProcessor.process(messages)
    }
}

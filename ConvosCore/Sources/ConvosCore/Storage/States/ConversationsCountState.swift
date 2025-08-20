import Combine
import Foundation
import Observation

// swiftlint:disable empty_count

@Observable
final class ConversationsCountState {
    private(set) var count: Int

    var isEmpty: Bool {
        count == 0
    }

    private let conversationsCountRepository: any ConversationsCountRepositoryProtocol
    private var cancellables: Set<AnyCancellable> = .init()

    init(conversationsCountRepository: any ConversationsCountRepositoryProtocol) {
        self.conversationsCountRepository = conversationsCountRepository
        do {
            self.count = try conversationsCountRepository.fetchCount()
        } catch {
            Logger.error("Error fetching conversations count: \(error)")
            self.count = 0
        }
        observe()
    }

    private func observe() {
        conversationsCountRepository.conversationsCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in
                guard let self else { return }
                self.count = count
            }
            .store(in: &cancellables)
    }
}

// swiftlint:enable empty_count

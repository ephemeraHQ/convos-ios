import Combine

extension Publisher {
    /// Emits a tuple of the previous and current values of the publisher.
    func withPrevious() -> AnyPublisher<(Output, Output), Failure> {
        self.scan(nil as (Output, Output)?) { previous, current in
            guard let previous = previous else {
                return (current, current)
            }
            return (previous.1, current)
        }
        .compactMap { $0 }
        .eraseToAnyPublisher()
    }
}

final class PublisherValue<T> {
    private let subject: CurrentValueSubject<T?, Never>
    private var cancellable: AnyCancellable?

    var value: T? {
        subject.value
    }

    var publisher: AnyPublisher<T?, Never> {
        subject.eraseToAnyPublisher()
    }

    init(initial: T?, upstream: AnyPublisher<T, Never>) {
        subject = CurrentValueSubject(initial)
        cancellable = upstream.sink { [weak subject] value in
            subject?.send(value)
        }
    }

    deinit {
        cancellable?.cancel()
        cancellable = nil
    }
}

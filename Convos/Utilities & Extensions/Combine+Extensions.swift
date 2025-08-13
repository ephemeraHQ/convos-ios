import Combine

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

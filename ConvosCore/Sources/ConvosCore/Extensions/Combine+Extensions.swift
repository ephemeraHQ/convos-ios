import Combine

final class PublisherValue<T> {
    private let subject: CurrentValueSubject<T?, Never>
    private var cancellable: AnyCancellable?
    private var isDisposed: Bool = false

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
        dispose()
    }

    func dispose() {
        guard !isDisposed else { return }
        isDisposed = true
        cancellable?.cancel()
        cancellable = nil
        subject.send(completion: .finished)
    }
}

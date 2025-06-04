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

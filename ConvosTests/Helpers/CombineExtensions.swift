import Combine

enum WaitForMatchError: Error {
    case timeout
}

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

    func waitForFirstMatch(
        where predicate: @escaping (Output) -> Bool,
        timeout: Duration = .seconds(2)
    ) async throws -> Output {
        try await withThrowingTaskGroup(of: Output.self) { group in
            group.addTask {
                for try await value in self.values {
                    if predicate(value) {
                        return value
                    }
                }
                throw CancellationError() // should never complete normally
            }

            group.addTask {
                try await Task.sleep(for: timeout)
                throw WaitForMatchError.timeout
            }

            let match = try await group.next()!
            group.cancelAll()
            return match
        }
    }
}

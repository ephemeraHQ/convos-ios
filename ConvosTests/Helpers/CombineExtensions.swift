import Combine

enum WaitForMatchError: Error {
    case timeout
}

extension Publisher where Output: Sendable {
    func waitForFirstMatch(
        where predicate: @escaping (Output) -> Bool,
        timeout: Duration = .seconds(2)
    ) async throws -> Output {
        return try await withThrowingTaskGroup(of: Output.self) { group in
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

import Foundation

// Helper function to add timeout to async operations
func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async -> T?) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask {
            await operation()
        }

        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return nil
        }

        if let result = await group.next() {
            group.cancelAll()
            return result
        } else {
            group.cancelAll()
            return nil
        }
    }
}

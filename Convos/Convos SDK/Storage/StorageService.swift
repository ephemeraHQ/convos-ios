import Foundation

public extension ConvosSDK {
    protocol StorageServiceProtocol {
        func save<T: Encodable>(_ value: T, for key: String) throws
        func retrieve<T: Decodable>(_ key: String) throws -> T?
        func delete(_ key: String) throws
    }
}

import Foundation

class MockProfileSearchRepository: ProfileSearchRepositoryProtocol {
    func search(using query: String) async throws -> [Profile] {
        return []
    }
}

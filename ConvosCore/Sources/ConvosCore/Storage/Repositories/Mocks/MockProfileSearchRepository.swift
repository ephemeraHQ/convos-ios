import Foundation

class MockProfileSearchRepository: ProfileSearchRepositoryProtocol {
    func search(using query: String) async throws -> [ProfileSearchResult] {
        return []
    }
}

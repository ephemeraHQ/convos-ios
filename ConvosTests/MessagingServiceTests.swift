import Testing
@testable import Convos

struct MessagingServiceTests {
    func makeClient(
        authService: MockAuthService = MockAuthService()
    ) -> ConvosClient {
        .testClient(authService: authService)
    }

    @Test("Registering a user starts the messaging service")
    func testRegisteringUserStartsService() async throws {
        let authService = MockAuthService()
        let client = makeClient(authService: authService)
        var stateIterator = client.messaging
            .messagingStatePublisher()
            .values
            .makeAsyncIterator()
        try await client.register(displayName: "Name")
        #expect(authService.currentUser?.displayName == "Name")
        let first = await stateIterator.next()
        #expect(first == .uninitialized)
        let second = await stateIterator.next()
        #expect(second == .initializing)
        let third = await stateIterator.next()
        #expect(third == .authorizing)
        let fourth = await stateIterator.next()
        #expect(fourth == .ready)
    }
}

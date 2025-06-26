@testable import Convos
import Testing

struct InboxStateMachineTests {
    @Test("Registering a user creates a new inbox")
    func testRegisteringUser() async throws {
        let mockAuthResult = MockAuthResult(name: "Name")
        let inbox = mockAuthResult.inbox
        let syncingManager = MockSyncingManager()
        let databaseWriter = MockDatabaseManager.shared.dbWriter
        let inboxWriter = InboxWriter(databaseWriter: databaseWriter)
        let inboxStateMachine = InboxStateMachine(
            inbox: inbox,
            inboxWriter: inboxWriter,
            syncingManager: syncingManager,
            sessionType: .external,
            environment: .tests
        )
        var stateIterator = inboxStateMachine.statePublisher.values.makeAsyncIterator()
        let first = await stateIterator.next()
        #expect(first == .uninitialized)
        await inboxStateMachine.register(displayName: "Name")
        let second = await stateIterator.next()
        #expect(second == .initializing)
        let third = await stateIterator.next()
        #expect(third == .authorizing)
        let fourth = await stateIterator.next()
        #expect(fourth == .registering)
        guard let fifth = await stateIterator.next() else {
            fatalError()
        }
        #expect(fifth.isReady)
        if case let .ready(result) = fifth {
            let inboxesRepository = InboxesRepository(
                databaseReader: MockDatabaseManager.shared.dbReader
            )
            let inboxes = try inboxesRepository.allInboxes()
            let foundInbox = inboxes.first(where: { $0.inboxId == result.client.inboxId })
            #expect(foundInbox != nil)
        } else {
            fatalError()
        }
    }

    @Test("Signing in an existing user")
    func testSigningIn() async throws {
        let mockAuthResult = MockAuthResult(name: "Name")
        let inbox = mockAuthResult.inbox
        let syncingManager = MockSyncingManager()
        let databaseWriter = MockDatabaseManager.shared.dbWriter
        let inboxWriter = InboxWriter(databaseWriter: databaseWriter)
        let inboxStateMachine = InboxStateMachine(
            inbox: inbox,
            inboxWriter: inboxWriter,
            syncingManager: syncingManager,
            sessionType: .external,
            environment: .tests
        )
        var stateIterator = inboxStateMachine.statePublisher.values.makeAsyncIterator()
        let first = await stateIterator.next()
        #expect(first == .uninitialized)
        await inboxStateMachine.register(displayName: "Name")
        let second = await stateIterator.next()
        #expect(second == .initializing)
        let third = await stateIterator.next()
        #expect(third == .authorizing)
        let fourth = await stateIterator.next()
        #expect(fourth == .registering)
        guard let fifth = await stateIterator.next() else {
            fatalError()
        }
        #expect(fifth.isReady)

        let signInStateMachine = InboxStateMachine(
            inbox: inbox,
            inboxWriter: inboxWriter,
            syncingManager: syncingManager,
            sessionType: .external,
            environment: .tests
        )
        var signInStateIterator = signInStateMachine.statePublisher.values.makeAsyncIterator()
        _ = await signInStateIterator.next() // uninitialized
        await signInStateMachine.authorize()
        let signInFirst = await signInStateIterator.next()
        #expect(signInFirst == .initializing)
        let signInSecond = await signInStateIterator.next()
        #expect(signInSecond == .authorizing)
        guard let signInThird = await signInStateIterator.next() else {
            fatalError()
        }
        #expect(signInThird.isReady)
    }
}

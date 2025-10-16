@testable import Convos
import Testing

struct InboxStateMachineTests {
    @Test("Registering a user creates a new inbox")
    func testRegisteringUser() async throws {
        Logger.info("🔍 Starting test: Registering a user creates a new inbox")

        let mockAuthResult = MockAuthResult(name: "Name")
        let inbox = mockAuthResult.inbox
        let syncingManager = MockSyncingManager()
        let databaseWriter = MockDatabaseManager.shared.dbWriter
        let inboxWriter = InboxWriter(databaseWriter: databaseWriter)
        let inboxStateMachine = InboxStateMachine(
            inbox: inbox,
            inboxWriter: inboxWriter,
            syncingManager: syncingManager,
            environment: .tests
        )

        // Set up state iterator with timeout
        var stateIterator = inboxStateMachine.statePublisher.values.makeAsyncIterator()

        // Wait for initial state with timeout
        Logger.info("🔍 Waiting for initial state...")
        let first = await withTimeout(seconds: 10) {
            await stateIterator.next()
        }
        Logger.info("🔍 Got initial state: \(String(describing: first))")
        #expect(first == .uninitialized)

        // Start registration
        Logger.info("🔍 Starting registration...")
        await inboxStateMachine.register(displayName: "Name")

        // Wait for state transitions with timeouts
        Logger.info("🔍 Waiting for initializing state...")
        let second = await withTimeout(seconds: 10) {
            await stateIterator.next()
        }
        Logger.info("🔍 Got second state: \(String(describing: second))")
        #expect(second == .initializing)

        Logger.info("🔍 Waiting for authorizing state...")
        let third = await withTimeout(seconds: 10) {
            await stateIterator.next()
        }
        Logger.info("🔍 Got third state: \(String(describing: third))")
        if case .authorizing = third {
            // Expected state
        } else {
            #expect(Bool(false), "Expected .authorizing state, got \(String(describing: third))")
        }

        Logger.info("🔍 Waiting for registering state...")
        let fourth = await withTimeout(seconds: 10) {
            await stateIterator.next()
        }
        Logger.info("🔍 Got fourth state: \(String(describing: fourth))")
        #expect(fourth == .registering)

        Logger.info("🔍 Waiting for ready state...")
        let fifth = await withTimeout(seconds: 10) {
            await stateIterator.next()
        }
        Logger.info("🔍 Got fifth state: \(String(describing: fifth))")
        #expect(fifth?.isReady == true)

        if case let .ready(result) = fifth {
            Logger.info("🔍 Checking inbox in database...")
            let inboxesRepository = InboxesRepository(
                databaseReader: MockDatabaseManager.shared.dbReader
            )
            let inboxes = try inboxesRepository.allInboxes()
            let foundInbox = inboxes.first(where: { $0.inboxId == result.client.inboxId })
            #expect(foundInbox != nil)
            Logger.info("🔍 Test completed successfully")
        } else {
            #expect(false, "Expected ready state but got \(String(describing: fifth))")
        }
    }

    @Test("Signing in an existing user")
    func testSigningIn() async throws {
        Logger.info("🔍 Starting test: Signing in an existing user")

        let mockAuthResult = MockAuthResult(name: "Name")
        let inbox = mockAuthResult.inbox
        let syncingManager = MockSyncingManager()
        let databaseWriter = MockDatabaseManager.shared.dbWriter
        let inboxWriter = InboxWriter(databaseWriter: databaseWriter)
        let inboxStateMachine = InboxStateMachine(
            inbox: inbox,
            inboxWriter: inboxWriter,
            syncingManager: syncingManager,
            environment: .tests
        )

        // Set up state iterator with timeout
        var stateIterator = inboxStateMachine.statePublisher.values.makeAsyncIterator()

        // Wait for initial state with timeout
        Logger.info("🔍 Waiting for initial state...")
        let first = await withTimeout(seconds: 10) {
            await stateIterator.next()
        }
        Logger.info("🔍 Got initial state: \(String(describing: first))")
        #expect(first == .uninitialized)

        // Start registration first to create the user
        Logger.info("🔍 Starting registration...")
        await inboxStateMachine.register(displayName: "Name")

        // Wait for registration to complete with timeouts
        Logger.info("🔍 Waiting for registration states...")
        let second = await withTimeout(seconds: 10) {
            await stateIterator.next()
        }
        Logger.info("🔍 Got second state: \(String(describing: second))")
        #expect(second == .initializing)

        let third = await withTimeout(seconds: 10) {
            await stateIterator.next()
        }
        Logger.info("🔍 Got third state: \(String(describing: third))")
        if case .authorizing = third {
            // Expected state
        } else {
            #expect(Bool(false), "Expected .authorizing state, got \(String(describing: third))")
        }

        let fourth = await withTimeout(seconds: 10) {
            await stateIterator.next()
        }
        Logger.info("🔍 Got fourth state: \(String(describing: fourth))")
        #expect(fourth == .registering)

        let fifth = await withTimeout(seconds: 10) {
            await stateIterator.next()
        }
        Logger.info("🔍 Got fifth state: \(String(describing: fifth))")
        #expect(fifth?.isReady == true)

        // Now test sign in with a new state machine
        Logger.info("🔍 Creating new state machine for sign in test...")
        let signInStateMachine = InboxStateMachine(
            inbox: inbox,
            inboxWriter: inboxWriter,
            syncingManager: syncingManager,
            environment: .tests
        )

        var signInStateIterator = signInStateMachine.statePublisher.values.makeAsyncIterator()

        // Wait for initial state with timeout
        Logger.info("🔍 Waiting for sign in initial state...")
        let signInFirst = await withTimeout(seconds: 10) {
            await signInStateIterator.next()
        }
        Logger.info("🔍 Got sign in initial state: \(String(describing: signInFirst))")
        #expect(signInFirst == .uninitialized)

        // Start authorization
        Logger.info("🔍 Starting authorization...")
        await signInStateMachine.authorize()

        let signInSecond = await withTimeout(seconds: 10) {
            await signInStateIterator.next()
        }
        Logger.info("🔍 Got sign in second state: \(String(describing: signInSecond))")
        #expect(signInSecond == .initializing)

        let signInThird = await withTimeout(seconds: 10) {
            await signInStateIterator.next()
        }
        Logger.info("🔍 Got sign in third state: \(String(describing: signInThird))")
        if case .authorizing = signInThird {
            // Expected state
        } else {
            #expect(Bool(false), "Expected .authorizing state, got \(String(describing: signInThird))")
        }

        let signInFourth = await withTimeout(seconds: 10) {
            await signInStateIterator.next()
        }
        Logger.info("🔍 Got sign in fourth state: \(String(describing: signInFourth))")
        #expect(signInFourth?.isReady == true)

        Logger.info("🔍 Sign in test completed successfully")
    }
}

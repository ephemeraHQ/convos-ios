import ConvosCore
import Foundation
import Testing

/// Test suite for KeychainIdentityStore
@Suite(.serialized) class KeychainIdentityStoreExampleTests {
    // MARK: - Test Properties

    private let keychainStore: KeychainIdentityStore
    private let testAccessGroup: String = "FY4NZR34Z3.org.convos.KeychainIdentityStoreExample"
    private let testService: String = "org.convos.KeychainIdentityStoreExample.service"

    init() throws {
        keychainStore = KeychainIdentityStore(accessGroup: testAccessGroup, service: testService)
    }

    deinit {
        try? keychainStore.deleteAll()
    }

    // MARK: - Helper Methods

    private func createKeychainStore() -> KeychainIdentityStoreProtocol {
        return KeychainIdentityStore(accessGroup: testAccessGroup, service: testService)
    }

    // MARK: - Identity Management Tests

    @Test func testSaveAndLoadIdentity() async throws {
        // When
        let savedIdentity = try keychainStore.save()

        // Then
        #expect(!savedIdentity.id.isEmpty)
        #expect(savedIdentity.databaseKey.count == 32) // 256-bit key

        // Verify we can load the identity
        let loadedIdentity = try keychainStore.load(for: savedIdentity.id)
        #expect(loadedIdentity != nil)
        #expect(loadedIdentity?.id == savedIdentity.id)
        #expect(loadedIdentity?.databaseKey == savedIdentity.databaseKey)
    }

    @Test func testLoadNonExistentIdentity() async throws {
        // Given
        let nonExistentId = UUID().uuidString

        // When
        let loadedIdentity = try keychainStore.load(for: nonExistentId)

        // Then
        #expect(loadedIdentity == nil)
    }

    @Test func testLoadAllIdentities() async throws {
        // Given
        let identity1 = try keychainStore.save()
        let identity2 = try keychainStore.save()
        let identity3 = try keychainStore.save()

        // When
        let allIdentities = try keychainStore.loadAll()

        // Then
        #expect(allIdentities.count == 3)
        #expect(allIdentities.contains { $0.id == identity1.id })
        #expect(allIdentities.contains { $0.id == identity2.id })
        #expect(allIdentities.contains { $0.id == identity3.id })
    }

    @Test func testLoadAllIdentitiesWhenEmpty() async throws {
        // When
        let allIdentities = try keychainStore.loadAll()

        // Then
        #expect(allIdentities.isEmpty)
    }

    @Test func testDeleteIdentity() async throws {
        // Given
        let identity = try keychainStore.save()
        #expect(try keychainStore.load(for: identity.id) != nil)

        // When
        try keychainStore.delete(for: identity.id)

        // Then
        #expect(try keychainStore.load(for: identity.id) == nil)

        // Verify it's not in the list
        let allIdentities = try keychainStore.loadAll()
        #expect(!allIdentities.contains { $0.id == identity.id })
    }

    @Test func testDeleteNonExistentIdentity() async throws {
        // Given
        let nonExistentId = UUID().uuidString

        // When & Then - Should not throw
        try keychainStore.delete(for: nonExistentId)
    }

    // MARK: - Inbox ID Management Tests

    @Test func testSaveAndLoadInboxId() async throws {
        // Given
        let identity = try keychainStore.save()
        let inboxId = "test-inbox-123"

        // When
        try keychainStore.save(inboxId: inboxId, for: identity.id)
        let loadedInboxId = try keychainStore.loadInboxId(for: identity.id)

        // Then
        #expect(loadedInboxId == inboxId)
    }

    @Test func testLoadInboxIdForNonExistentIdentity() async throws {
        // Given
        let nonExistentId = UUID().uuidString

        // When & Then
        do {
            _ = try keychainStore.loadInboxId(for: nonExistentId)
            #expect(Bool(false), "Expected error when loading inbox ID for non-existent identity")
        } catch {
            // Expected to throw an error
            #expect(error is KeychainIdentityStoreError)
        }
    }

    @Test func testInboxIdIsCaseInsensitive() async throws {
        // Given
        let identity = try keychainStore.save()
        let inboxId = "Test-Inbox-123"

        // When
        try keychainStore.save(inboxId: inboxId, for: identity.id.uppercased())
        let loadedInboxId = try keychainStore.loadInboxId(for: identity.id.lowercased())

        // Then
        #expect(loadedInboxId == inboxId)
    }

    // MARK: - Provider ID Management Tests

    @Test func testSaveAndLoadProviderId() async throws {
        // Given
        let inboxId = "test-inbox-456"
        let providerId = "provider-789"

        // When
        try keychainStore.save(providerId: providerId, for: inboxId)
        let loadedProviderId = try keychainStore.loadProviderId(for: inboxId)

        // Then
        #expect(loadedProviderId == providerId)
    }

    @Test func testLoadProviderIdForNonExistentInbox() async throws {
        // Given
        let nonExistentInboxId = "non-existent-inbox"

        // When & Then
        do {
            _ = try keychainStore.loadProviderId(for: nonExistentInboxId)
            #expect(Bool(false), "Expected error when loading provider ID for non-existent inbox")
        } catch {
            // Expected to throw an error
            #expect(error is KeychainIdentityStoreError)
        }
    }

    @Test func testDeleteProviderId() async throws {
        // Given
        let inboxId = "test-inbox-789"
        let providerId = "provider-123"
        try keychainStore.save(providerId: providerId, for: inboxId)
        #expect(try keychainStore.loadProviderId(for: inboxId) == providerId)

        // When
        try keychainStore.deleteProviderId(for: inboxId)

        // Then
        do {
            _ = try keychainStore.loadProviderId(for: inboxId)
            #expect(Bool(false), "Expected error when loading deleted provider ID")
        } catch {
            // Expected to throw an error
            #expect(error is KeychainIdentityStoreError)
        }
    }

    @Test func testDeleteProviderIdForNonExistentInbox() async throws {
        // Given
        let nonExistentInboxId = "non-existent-inbox"

        // When & Then - Should not throw
        try keychainStore.deleteProviderId(for: nonExistentInboxId)
    }

    // MARK: - Error Handling Tests

    @Test func testConcurrentIdentityOperations() async throws {
        // Given
        let numberOfIdentities = 10

        // When - Create multiple identities concurrently
        let identities = try await withThrowingTaskGroup(of: KeychainIdentity.self) { group in
            for _ in 0..<numberOfIdentities {
                group.addTask {
                    try self.keychainStore.save()
                }
            }

            var results: [KeychainIdentity] = []
            for try await identity in group {
                results.append(identity)
            }
            return results
        }

        // Then
        #expect(identities.count == numberOfIdentities)

        // Verify all identities are unique
        let ids = Set(identities.map { $0.id })
        #expect(ids.count == numberOfIdentities)

        // Verify we can load all identities
        let loadedIdentities = try keychainStore.loadAll()
        #expect(loadedIdentities.count == numberOfIdentities)
    }

    // MARK: - Data Persistence Tests

    @Test func testIdentityPersistenceAcrossInstances() async throws {
        // Given
        let identity = try keychainStore.save()
        let inboxId = "persistent-inbox"
        let providerId = "persistent-provider"

        try keychainStore.save(inboxId: inboxId, for: identity.id)
        try keychainStore.save(providerId: providerId, for: inboxId)

        // When - Create a new instance
        let newKeychainStore = createKeychainStore()

        // Then - Data should persist
        let loadedIdentity = try newKeychainStore.load(for: identity.id)
        #expect(loadedIdentity != nil)
        #expect(loadedIdentity?.id == identity.id)

        let loadedInboxId = try newKeychainStore.loadInboxId(for: identity.id)
        #expect(loadedInboxId == inboxId)

        let loadedProviderId = try newKeychainStore.loadProviderId(for: inboxId)
        #expect(loadedProviderId == providerId)
    }

    // MARK: - Edge Cases Tests

    @Test func testVeryLongIdentityId() async throws {
        // Given
        let longId = String(repeating: "a", count: 1000)
        let inboxId = "test-inbox"

        // When
        try keychainStore.save(inboxId: inboxId, for: longId)
        let loadedInboxId = try keychainStore.loadInboxId(for: longId)

        // Then
        #expect(loadedInboxId == inboxId)
    }

    @Test func testSpecialCharactersInInboxId() async throws {
        // Given
        let identity = try keychainStore.save()
        let inboxIdWithSpecialChars = "test-inbox!@#$%^&*()_+-=[]{}|;':\",./<>?"

        // When
        try keychainStore.save(inboxId: inboxIdWithSpecialChars, for: identity.id)
        let loadedInboxId = try keychainStore.loadInboxId(for: identity.id)

        // Then
        #expect(loadedInboxId == inboxIdWithSpecialChars)
    }

    @Test func testUnicodeCharactersInProviderId() async throws {
        // Given
        let inboxId = "test-inbox"
        let providerIdWithUnicode = "provider-🚀-🎉-🌟"

        // When
        try keychainStore.save(providerId: providerIdWithUnicode, for: inboxId)
        let loadedProviderId = try keychainStore.loadProviderId(for: inboxId)

        // Then
        #expect(loadedProviderId == providerIdWithUnicode)
    }

    // MARK: - Cleanup Tests

    @Test func testCompleteCleanup() async throws {
        // Given
        let identity1 = try keychainStore.save()
        let identity2 = try keychainStore.save()

        try keychainStore.save(inboxId: "inbox1", for: identity1.id)
        try keychainStore.save(inboxId: "inbox2", for: identity2.id)
        try keychainStore.save(providerId: "provider1", for: "inbox1")
        try keychainStore.save(providerId: "provider2", for: "inbox2")

        // Verify data exists
        #expect(try keychainStore.loadAll().count == 2)

        // When - Delete all identities
        try keychainStore.delete(for: identity1.id)
        try keychainStore.delete(for: identity2.id)

        // Then
        #expect(try keychainStore.loadAll().isEmpty)

        // Provider IDs should also be cleaned up
        do {
            _ = try keychainStore.loadProviderId(for: "inbox1")
            #expect(Bool(false), "Provider ID should be cleaned up")
        } catch {
            // Expected
        }

        do {
            _ = try keychainStore.loadProviderId(for: "inbox2")
            #expect(Bool(false), "Provider ID should be cleaned up")
        } catch {
            // Expected
        }
    }

    @Test func testDeleteAll() async throws {
        // Given - Create multiple identities with associated data
        let identity1 = try keychainStore.save()
        let identity2 = try keychainStore.save()
        let identity3 = try keychainStore.save()

        try keychainStore.save(inboxId: "inbox1", for: identity1.id)
        try keychainStore.save(inboxId: "inbox2", for: identity2.id)
        try keychainStore.save(inboxId: "inbox3", for: identity3.id)

        try keychainStore.save(providerId: "provider1", for: "inbox1")
        try keychainStore.save(providerId: "provider2", for: "inbox2")
        try keychainStore.save(providerId: "provider3", for: "inbox3")

        // Verify data exists
        #expect(try keychainStore.loadAll().count == 3)
        #expect(try keychainStore.loadInboxId(for: identity1.id) == "inbox1")
        #expect(try keychainStore.loadProviderId(for: "inbox1") == "provider1")

        // When - Delete all data
        try keychainStore.deleteAll()

        // Then - All identities should be gone
        #expect(try keychainStore.loadAll().isEmpty)

        // Individual identities should not be loadable
        #expect(try keychainStore.load(for: identity1.id) == nil)
        #expect(try keychainStore.load(for: identity2.id) == nil)
        #expect(try keychainStore.load(for: identity3.id) == nil)

        // Inbox IDs should not be loadable
        do {
            _ = try keychainStore.loadInboxId(for: identity1.id)
            #expect(Bool(false), "Inbox ID should be cleaned up")
        } catch {
            // Expected
        }

        // Provider IDs should not be loadable
        do {
            _ = try keychainStore.loadProviderId(for: "inbox1")
            #expect(Bool(false), "Provider ID should be cleaned up")
        } catch {
            // Expected
        }
    }

    @Test func testDeleteAllWhenEmpty() async throws {
        // Given - Empty keychain store
        #expect(try keychainStore.loadAll().isEmpty)

        // When & Then - Should not throw when deleting all from empty store
        try keychainStore.deleteAll()
        #expect(try keychainStore.loadAll().isEmpty)
    }
}

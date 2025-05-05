import CryptoKit
import Foundation
import GRDB
import SwiftUI
import TurnkeySDK
import XMTPiOS

// swiftlint:disable force_unwrapping line_length

final class ClientManager {
    init() async throws {
    }
}

class CTIdentityStore: ObservableObject {
    @Published private(set) var currentIdentity: CTUser?
    @Published private(set) var availableIdentities: [CTUser] = []
    @Published var isIdentityPickerPresented: Bool = false

    private let dbQueue: DatabaseQueue

    init() throws {
        // Set up the database
        let fileManager = FileManager.default
        let folderURL = try fileManager
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Convos", isDirectory: true)

        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let dbURL = folderURL.appendingPathComponent("identities.sqlite")
        self.dbQueue = try DatabaseQueue(path: dbURL.path)

        // Create the table if it doesn't exist
        try dbQueue.write { db in
            try db.create(table: "users", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("username", .text).notNull()
                t.column("avatarURL", .text)
                t.column("isCurrent", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull()
                t.column("lastUsedAt", .datetime).notNull()
            }
        }

        // Load available identities
        try loadIdentities()
    }

    private func loadIdentities() throws {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM users ORDER BY lastUsedAt DESC")
            availableIdentities = rows.map { row in
                CTUser(
                    id: row["id"] as String,
                    username: row["username"] as String,
                    avatarURL: URL(string: row["avatarURL"] as String? ?? "")
                )
            }
            // Find the current identity
            if let currentRow = try Row.fetchOne(db, sql: "SELECT * FROM users WHERE isCurrent = 1") {
                currentIdentity = CTUser(
                    id: currentRow["id"] as String,
                    username: currentRow["username"] as String,
                    avatarURL: URL(string: currentRow["avatarURL"] as String? ?? "")
                )
            }
        }
    }

    // MARK: - Mock Data (for testing only)

    func createMockIdentities() throws {
        let mockIdentities = [
            CTUser(
                id: "identity1",
                username: "Convos",
                avatarURL: URL(string: "https://fastly.picsum.photos/id/913/200/200.jpg?hmac=MQWqYyJuxoagkUNdhY5lwuKw7QwcqzMEm4otshKpUWQ")!
            ),
            CTUser(
                id: "identity2",
                username: "Andrew",
                avatarURL: URL(string: "https://fastly.picsum.photos/id/677/200/200.jpg?hmac=x54KZ3q80hA0Sc36RV2FUoDZdE3R31oaC988MA1YE2s")!
            ),
            CTUser(
                id: "identity3",
                username: "Incognito",
                avatarURL: URL(string: "https://fastly.picsum.photos/id/686/200/200.jpg?hmac=5DMCllhAJj0gbXXcSZQLQZwnruDJDMVbmFqqwZ6wFug")!
            )
        ]

        try dbQueue.write { db in
            for (index, identity) in mockIdentities.enumerated() {
                try db.execute(
                    sql: """
                    INSERT INTO users (id, username, avatarURL, isCurrent, createdAt, lastUsedAt)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        identity.id,
                        identity.username,
                        identity.avatarURL?.absoluteString,
                        index == 0, // First identity is current
                        Date(),
                        Date()
                    ]
                )
            }
        }

        try loadIdentities()
    }

    func switchIdentity(to identity: CTUser) {
        try? dbQueue.write { db in
            // Set all identities to not current
            try db.execute(sql: "UPDATE users SET isCurrent = 0")

            // Set the selected identity as current
            try db.execute(
                sql: "UPDATE users SET isCurrent = 1, lastUsedAt = ? WHERE id = ?",
                arguments: [Date(), identity.id]
            )
        }

        try? loadIdentities()
        isIdentityPickerPresented = false
    }

    static func generateRandomPrivateKey() -> XMTPiOS.PrivateKey {
        let account = PrivateKey()
        return account
    }

    static func generateRandomDatabaseEncryptionKey() -> CryptoKit.SymmetricKey {
        let dbEncryptionKey = SymmetricKey(size: .bits256)
        return dbEncryptionKey
    }

    static func generateRandomClient() async throws -> XMTPiOS.Client {
        let account = CTIdentityStore.generateRandomPrivateKey()
        let dbEncryptionKey = CTIdentityStore.generateRandomDatabaseEncryptionKey()
        let clientOptions = ClientOptions(
            api: ClientOptions.Api(env: .production, isSecure: true),
            codecs: [],
            preAuthenticateToInboxCallback: nil,
            dbEncryptionKey: dbEncryptionKey.withUnsafeBytes { Data($0) },
            dbDirectory: nil,
            historySyncUrl: nil,
            useDefaultHistorySyncUrl: true
        )
        return try await XMTPiOS.Client.create(account: account, options: clientOptions)
    }
}

// swiftlint:enable force_unwrapping line_length

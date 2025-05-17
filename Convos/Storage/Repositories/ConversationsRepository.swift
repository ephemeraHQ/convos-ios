import Combine
import Foundation
import GRDB

protocol ConversationsRepositoryProtocol {
    func fetchAll() throws -> [Conversation]
    func conversationsPublisher() -> AnyPublisher<[Conversation], Never>
}

final class ConversationsRepository: ConversationsRepositoryProtocol {
    private let dbReader: any DatabaseReader

    init(dbReader: any DatabaseReader) {
        self.dbReader = dbReader
    }

    func fetchAll() throws -> [Conversation] {
        try dbReader.read { db in
            try db.composeAllConversations()
        }
    }

    func conversationsPublisher() -> AnyPublisher<[Conversation], Never> {
        ValueObservation
            .tracking { db in
                try db.composeAllConversations()
            }
            .publisher(in: dbReader)
            .replaceError(with: [])
            .eraseToAnyPublisher()
    }
}

fileprivate extension Database {
    func composeAllConversations() throws -> [Conversation] {
        let dbConversations = try DBConversation
            .fetchAll(self)

        let memberIds = dbConversations.flatMap { $0.memberIds }
        let creatorIds = dbConversations.map { $0.creatorId }
        let allProfileIds = Set(memberIds + creatorIds)

        let memberProfiles = try MemberProfile
            .filter(allProfileIds.contains(Column("inboxId")))
            .fetchAll(self)

        let currentUserProfile = try currentUserProfile()

        let profileById = Dictionary(uniqueKeysWithValues: memberProfiles.map { ($0.inboxId, $0) })
        let conversations: [Conversation] = try dbConversations.compactMap { dbConv in
            let creator: Profile
            if let creatorProfile = profileById[dbConv.creatorId] {
                creator = Profile(from: creatorProfile)
            } else {
                creator = .empty
            }

            // Find member profiles
            let members: [Profile] = dbConv.memberIds.map { memberId in
                profileById[memberId].map(Profile.init(from:)) ?? .empty
            }

            let localState = try ConversationLocalState
                .filter(Column("id") == dbConv.id)
                .fetchOne(self) ?? .empty

            let otherMemberProfile: Profile?
            if dbConv.kind == .dm,
               let currentUserProfile,
               let otherProfile = members.first(
                where: { $0.id != currentUserProfile.id }) {
                otherMemberProfile = otherProfile
            } else {
                otherMemberProfile = nil
            }

            let messages: [Message] = try Message
                .filter(Column("conversationId") == dbConv.id)
                .order(Column("date").asc)
                .fetchAll(self)
            let imageURL: URL?
            if let imageURLString = dbConv.imageURLString {
                imageURL = URL(string: imageURLString)
            } else {
                imageURL = nil
            }
            return Conversation(
                id: dbConv.id,
                creator: creator,
                kind: dbConv.kind,
                topic: dbConv.topic,
                members: members,
                otherMember: otherMemberProfile,
                messages: messages,
                isPinned: localState.isPinned,
                isUnread: localState.isUnread,
                isMuted: localState.isMuted,
                lastMessage: dbConv.lastMessage,
                imageURL: imageURL
            )
        }

        return conversations.sorted { (lhs, rhs) in
            let lhsDate = lhs.lastMessage?.createdAt ?? .distantPast
            let rhsDate = rhs.lastMessage?.createdAt ?? .distantPast
            return lhsDate > rhsDate
        }
    }
}

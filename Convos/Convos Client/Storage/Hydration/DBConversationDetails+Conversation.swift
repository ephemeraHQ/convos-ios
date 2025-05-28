import Foundation

extension DBConversationDetails {
    func hydrateConversation(currentUser: User) -> Conversation {
        let lastMessage: MessagePreview? = conversationLastMessage?.hydrateMessagePreview(
            conversationKind: conversation.kind
        )
        let creatorProfile = conversationCreatorProfile.hydrateProfile()

        let otherMemberProfile: Profile?
        if conversation.kind == .dm,
            let otherProfile = conversationMemberProfiles.first(
                where: { $0.inboxId != currentUser.profile.id }) {
            otherMemberProfile = otherProfile.hydrateProfile()
        } else {
            otherMemberProfile = nil
        }

        // we don't need messages for the conversations list
        let messages: [Message] = []

        let imageURL: URL?
        if let imageURLString = conversation.imageURLString {
            imageURL = URL(string: imageURLString)
        } else {
            imageURL = nil
        }

        return Conversation(
            id: conversation.id,
            creator: creatorProfile,
            createdAt: conversation.createdAt,
            kind: conversation.kind,
            name: conversation.name,
            description: conversation.description,
            members: conversationMemberProfiles.map { $0.hydrateProfile() },
            otherMember: otherMemberProfile,
            messages: messages,
            isPinned: conversationLocalState.isPinned,
            isUnread: conversationLocalState.isUnread,
            isMuted: conversationLocalState.isMuted,
            lastMessage: lastMessage,
            imageURL: imageURL
        )
    }
}

import Foundation

extension DBConversationDetails {
    func hydrateConversation() -> Conversation {
        let lastMessage: MessagePreview? = conversationLastMessage?.hydrateMessagePreview(
            conversationKind: conversation.kind
        )
        let creatorProfile = conversationCreatorProfile.hydrateProfile()

        let otherMemberProfile: Profile?
        if conversation.kind == .dm,
            let otherProfile = conversationMemberProfiles.first(
                where: { $0.inboxId != conversation.inboxId }) {
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

        let members = conversationMemberProfiles
            .filter { $0.inboxId != conversation.inboxId }
            .map { $0.hydrateProfile() }

        return Conversation(
            id: conversation.id,
            inboxId: conversation.inboxId,
            creator: creatorProfile,
            createdAt: conversation.createdAt,
            consent: conversation.consent,
            kind: conversation.kind,
            name: conversation.name,
            description: conversation.description,
            members: members,
            otherMember: otherMemberProfile,
            messages: messages,
            isPinned: conversationLocalState.isPinned,
            isUnread: conversationLocalState.isUnread,
            isMuted: conversationLocalState.isMuted,
            lastMessage: lastMessage,
            imageURL: imageURL,
            isDraft: conversation.isDraft
        )
    }
}

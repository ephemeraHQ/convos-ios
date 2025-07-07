import SwiftUI

struct AvatarView: View {
    let imageURL: URL?
    let fallbackName: String

    init(imageURL: URL?,
         fallbackName: String) {
        self.imageURL = imageURL
        self.fallbackName = fallbackName
    }

    var body: some View {
        AsyncImage(url: imageURL) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            MonogramView(name: fallbackName)
        }
        .aspectRatio(1.0, contentMode: .fit)
        .clipShape(Circle())
    }
}

struct ProfileAvatarView: View {
    private let avatar: AvatarData

    init(profile: Profile) {
        self.avatar = .init(
            id: profile.id,
            imageURL: profile.avatarURL,
            fallbackName: profile.displayName
        )
    }

    var body: some View {
        AvatarView(imageURL: avatar.imageURL,
                   fallbackName: avatar.fallbackName)
        .id(avatar.id)
    }
}

struct ConversationAvatarView: View {
    private let conversation: Conversation
    private let avatars: [AvatarData]

    init(conversation: Conversation) {
        self.conversation = conversation

        let membersToShow: [Profile]

        if conversation.kind == .group {
            // For groups, show all members including current user
            membersToShow = conversation.withCurrentUserIncluded().members
        } else {
            // For DMs, show only the other party
            membersToShow = conversation.members
        }

        self.avatars = membersToShow
            .sorted { $0.id < $1.id }
            .map {
                .init(
                    id: $0.id,
                    imageURL: $0.avatarURL,
                    fallbackName: $0.name
                )
            }
    }

    var body: some View {
        if conversation.kind == .group && conversation.imageURL != nil {
            // Show the group's custom image when available
            AvatarView(imageURL: conversation.imageURL, fallbackName: conversation.name ?? "Group")
        } else {
            // Show member avatars when no group image is set (for groups) or for DMs
            AvatarCloudView(avatars: avatars)
        }
    }
}

#Preview {
    let profile = Profile(
        id: "1",
        name: "John Doe",
        username: "johndoe",
        avatar: nil
    )

    ProfileAvatarView(profile: profile)
}

#Preview {
    let conversation = Conversation.mock(members: [.mock(), .mock()])
    ConversationAvatarView(conversation: conversation)
}

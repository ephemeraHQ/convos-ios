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
    let profile: Profile

    var body: some View {
        AvatarView(imageURL: profile.avatarURL,
                   fallbackName: profile.name)
    }

    init(profile: Profile) {
        self.profile = profile
    }
}

struct ConversationAvatarView: View {
    let conversation: Conversation

    var body: some View {
        AvatarCloudView(avatars: conversation.members.sorted { $0.name < $1.name }.map {
            .init(
                id: $0.id,
                imageURL: $0.avatarURL,
                fallbackName: $0.name
            )
        })
    }

    init(conversation: Conversation) {
        self.conversation = conversation
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

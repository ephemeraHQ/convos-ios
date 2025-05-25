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
        AvatarView(imageURL: conversation.imageURL,
                   fallbackName: conversation.title)
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

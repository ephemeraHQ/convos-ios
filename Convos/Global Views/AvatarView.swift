import SwiftUI

struct AvatarView: View {
    let imageURL: URL?
    let fallbackName: String
    let size: CGFloat

    init(imageURL: URL?,
         fallbackName: String,
         size: CGFloat = DesignConstants.ImageSizes.smallAvatar) {
        self.imageURL = imageURL
        self.fallbackName = fallbackName
        self.size = size
    }

    var body: some View {
        AsyncImage(url: imageURL) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            MonogramView(name: fallbackName)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

struct ProfileAvatarView: View {
    let profile: Profile
    let size: CGFloat

    var body: some View {
        AvatarView(imageURL: profile.avatarURL,
                   fallbackName: profile.name,
                   size: size)
    }

    init(profile: Profile,
         size: CGFloat = DesignConstants.ImageSizes.smallAvatar) {
        self.profile = profile
        self.size = size
    }
}

struct ConversationAvatarView: View {
    let conversation: Conversation
    let size: CGFloat

    var body: some View {
        AvatarView(imageURL: conversation.imageURL,
                   fallbackName: conversation.title,
                   size: size)
    }

    init(conversation: Conversation,
         size: CGFloat = DesignConstants.ImageSizes.smallAvatar) {
        self.conversation = conversation
        self.size = size
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

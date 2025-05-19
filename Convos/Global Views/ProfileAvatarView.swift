import SwiftUI

struct ProfileAvatarView: View {
    let profile: Profile
    let size: CGFloat

    init(profile: Profile, size: CGFloat = DesignConstants.ImageSizes.smallAvatar) {
        self.profile = profile
        self.size = size
    }

    var body: some View {
        AsyncImage(url: profile.avatarURL) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            MonogramView(name: profile.name)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
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

import SwiftUI

struct AvatarView: View {
    let imageURL: URL?
    let fallbackName: String
    @State private var cachedImage: UIImage?
    @State private var isLoading: Bool = false

    init(imageURL: URL?,
         fallbackName: String) {
        self.imageURL = imageURL
        self.fallbackName = fallbackName
    }

    var body: some View {
        Group {
            if let cachedImage {
                Image(uiImage: cachedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                MonogramView(name: fallbackName)
                    .opacity(isLoading ? 0.7 : 1.0)
            }
        }
        .aspectRatio(1.0, contentMode: .fit)
        .clipShape(Circle())
        .task(id: imageURL) {
            await loadImage()
        }
    }

    @MainActor
    private func loadImage() async {
        guard let imageURL else {
            cachedImage = nil
            return
        }

        // Check if we already have this image
        if let existingImage = ImageCache.shared.image(for: imageURL) {
            cachedImage = existingImage
            return
        }

        isLoading = true

        do {
            let (data, _) = try await URLSession.shared.data(from: imageURL)
            if let image = UIImage(data: data) {
                // Cache the image for future use
                ImageCache.shared.setImage(image, for: imageURL)
                cachedImage = image
            }
        } catch {
            // Keep showing monogram on error
            cachedImage = nil
        }

        isLoading = false
    }
}

// MARK: - Simple Image Cache
/// Smart image cache that eliminates avatar flickering by showing cached images instantly
///
/// No manual invalidation needed - new uploads get new URLs (with UUID), so AvatarView
/// automatically loads fresh images when `.task(id: imageURL)` re-runs with the new URL

final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 100 // Limit to 100 images
        cache.totalCostLimit = 50 * 1024 * 1024 // 50 MB limit
    }

    func image(for url: URL) -> UIImage? {
        return cache.object(forKey: url.absoluteString as NSString)
    }

    func setImage(_ image: UIImage, for url: URL) {
        let cost = Int(image.size.width * image.size.height * 4) // Estimate memory usage
        cache.setObject(image, forKey: url.absoluteString as NSString, cost: cost)
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

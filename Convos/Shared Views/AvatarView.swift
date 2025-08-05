import Combine
import Observation
import SwiftUI

struct AvatarView: View {
    let imageURL: URL?
    let fallbackName: String
    let cacheableObject: (any ImageCacheable)?
    let cachedImage: UIImage?
    @State private var isLoading: Bool = false

    var body: some View {
        Group {
            if let cachedImage {
                Image(uiImage: cachedImage)
                    .resizable()
                    .scaledToFit()
                    .aspectRatio(contentMode: .fill)
            } else {
                MonogramView(name: fallbackName)
                    .opacity(isLoading ? 0.7 : 1.0)
            }
        }
        .aspectRatio(1.0, contentMode: .fit)
        .clipShape(Circle())
//        .task(id: imageURL) {
//            await loadImage()
//        }
//        .onAppear {
//            if let cacheableObject = cacheableObject {
//                cachedImage = ImageCache.shared.image(for: cacheableObject)
//            }
//        }
//        .onReceive(
//            ImageCache.shared.cacheUpdates
//                .receive(on: DispatchQueue.main)
//                .compactMap { [cacheableObject] identifier in
//                    cacheableObject?.imageCacheIdentifier == identifier ? identifier : nil
//                }
//        ) { _ in
//            if let cacheableObject = cacheableObject {
//                cachedImage = ImageCache.shared.image(for: cacheableObject)
//                if cachedImage == nil && imageURL != nil {
//                    Task {
//                        await loadImage()
//                    }
//                }
//            }
//        }
    }

//    @MainActor
//    private func loadImage() async {
//        // First check object cache for instant updates
//        if let cacheableObject = cacheableObject,
//           let cachedObjectImage = ImageCache.shared.image(for: cacheableObject) {
//            cachedImage = cachedObjectImage
//            return
//        }
//
//        guard let imageURL else {
//            cachedImage = nil
//            return
//        }
//
//        // Check URL-based cache
//        if let existingImage = ImageCache.shared.image(for: imageURL) {
//            cachedImage = existingImage
//            return
//        }
//
//        isLoading = true
//
//        do {
//            let (data, _) = try await URLSession.shared.data(from: imageURL)
//            if let image = UIImage(data: data) {
//                // Cache the image for future use
//                ImageCache.shared.setImage(image, for: imageURL.absoluteString)
//
//                // Also cache by object if available for instant cross-view updates
//                if let cacheableObject = cacheableObject {
//                    ImageCache.shared.setImage(image, for: cacheableObject)
//                }
//
//                cachedImage = image
//            }
//        } catch {
//            // Keep showing monogram on error
//            cachedImage = nil
//        }
//
//        isLoading = false
//    }
}

struct ProfileAvatarView: View {
    private let profile: Profile

    init(profile: Profile) {
        self.profile = profile
    }

    var body: some View {
        AvatarView(
            imageURL: profile.avatarURL,
            fallbackName: profile.displayName,
            cacheableObject: profile,
            cachedImage: nil
        )
        .id(profile.id)
    }
}

struct ConversationAvatarView: View {
    private let conversation: Conversation
    private let avatars: [AvatarData]
    @State private var conversationImage: UIImage?

    init(conversation: Conversation) {
        self.conversation = conversation

        let membersToShow: [ConversationMember]

        if conversation.kind == .group {
            // For groups, show all members including current user
            membersToShow = conversation.members
        } else {
            // For DMs, show only the other party
            membersToShow = conversation.membersWithoutCurrent
        }

        self.avatars = membersToShow
            .map { $0.profile }
            .sorted { $0.id < $1.id }
            .map {
                .init(
                    id: $0.imageCacheIdentifier,
                    imageURL: $0.avatarURL,
                    fallbackName: $0.displayName
                )
            }
    }

    var body: some View {
        Group {
            if conversation.kind == .group {
                // For groups, prioritize conversation cache, then URL
                if let conversationImage {
                    // Show cached conversation image instantly
                    Image(uiImage: conversationImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .aspectRatio(1.0, contentMode: .fit)
                        .clipShape(Circle())
                } else if conversation.imageURL != nil {
                    // Fall back to URL-based loading with conversation object for cache awareness
                    AvatarView(
                        imageURL: conversation.imageURL,
                        fallbackName: conversation.name ?? "Untitled",
                        cacheableObject: conversation,
                        cachedImage: conversationImage
                    )
                } else {
                    MonogramView(text: "")
                }
            } else {
                // Show member avatars for DMs
                AvatarCloudView(avatars: avatars)
            }
        }
    }
}

#Preview {
    @Previewable @State var profileImage: UIImage?
    let profile = Profile(
        inboxId: "1",
        name: "John Doe",
        username: "johndoe",
        avatar: nil
    )

    ProfileAvatarView(profile: profile)
}

#Preview {
    @Previewable @State var conversationImage: UIImage?
    let conversation = Conversation.mock(members: [.mock(), .mock()])
    ConversationAvatarView(conversation: conversation)
}

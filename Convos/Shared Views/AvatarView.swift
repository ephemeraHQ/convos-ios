import Combine
import Observation
import SwiftUI

struct AvatarView: View {
    let imageURL: URL?
    let fallbackName: String
    let conversationId: String?
    @State private var cachedImage: UIImage?
    @State private var isLoading: Bool = false

    init(imageURL: URL?,
         fallbackName: String,
         conversationId: String? = nil) {
        self.imageURL = imageURL
        self.fallbackName = fallbackName
        self.conversationId = conversationId
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
        .onChange(of: ImageCache.shared.lastUpdateTime) { _, _ in
            // When cache updates, check if we now have our image (URL or conversation-based)
            let hasURLImage: Bool = {
                guard let imageURL = imageURL else { return false }
                return ImageCache.shared.image(for: imageURL) != nil
            }()
            let hasConversationImage: Bool = {
                guard let conversationId = conversationId else { return false }
                return ImageCache.shared.imageForConversation(conversationId) != nil
            }()

            if hasURLImage || hasConversationImage {
                Task {
                    await loadImage()
                }
            }
        }
    }

    @MainActor
    private func loadImage() async {
        // First check conversation cache for instant updates
        if let conversationId = conversationId,
           let conversationImage = ImageCache.shared.imageForConversation(conversationId) {
            cachedImage = conversationImage
            return
        }

        guard let imageURL else {
            cachedImage = nil
            return
        }

        // Check URL-based cache
        if let existingImage = ImageCache.shared.image(for: imageURL) {
            cachedImage = existingImage
            return
        }

        isLoading = true

        do {
            let (data, _) = try await URLSession.shared.data(from: imageURL)
            if let image = UIImage(data: data) {
                // Cache the image for future use
                ImageCache.shared.setImage(image, for: imageURL.absoluteString)

                // Also cache by conversation ID if available for instant cross-view updates
                if let conversationId = conversationId {
                    ImageCache.shared.setImageForConversation(image, conversationId: conversationId)
                }

                cachedImage = image
            }
        } catch {
            // Keep showing monogram on error
            cachedImage = nil
        }

        isLoading = false
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
                    id: $0.id,
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
                    // Fall back to URL-based loading with conversation ID for cache awareness
                    AvatarView(
                        imageURL: conversation.imageURL,
                        fallbackName: conversation.name ?? "Group",
                        conversationId: conversation.id
                    )
                } else {
                    // No group image set, show member avatars
                    AvatarCloudView(avatars: avatars)
                }
            } else {
                // Show member avatars for DMs
                AvatarCloudView(avatars: avatars)
            }
        }
        .onAppear {
            loadConversationImage()
        }
        .onChange(of: ImageCache.shared.lastUpdateTime) { _, _ in
            loadConversationImage()
        }
    }

    private func loadConversationImage() {
        // Check conversation-based cache first for instant updates
        if let cachedImage = ImageCache.shared.imageForConversation(conversation.id) {
            conversationImage = cachedImage
        } else {
            conversationImage = nil
        }
    }
}

#Preview {
    let profile = Profile(
        inboxId: "1",
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

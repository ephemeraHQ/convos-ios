import Combine
import ConvosCore
import Observation
import SwiftUI

struct AvatarView: View {
    let imageURL: URL?
    let fallbackName: String
    let cacheableObject: any ImageCacheable
    @State private var cachedImage: UIImage?
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
        .task(id: imageURL) {
            await loadImage()
        }
        .cachedImage(for: cacheableObject) { image in
            cachedImage = image
        }
    }

    @MainActor
    private func loadImage() async {
        // First check object cache for instant updates
        if let cachedObjectImage = ImageCache.shared.image(for: cacheableObject) {
            cachedImage = cachedObjectImage
            return
        }

        guard let imageURL else {
            return
        }

        // Check URL-based cache
        if let existingImage = ImageCache.shared.image(for: imageURL) {
            cachedImage = existingImage
        }

        isLoading = true

        do {
            let (data, _) = try await URLSession.shared.data(from: imageURL)
            if let image = UIImage(data: data) {
                // Cache the image for future use
                ImageCache.shared.setImage(image, for: imageURL.absoluteString)

                // Also cache by object if available for instant cross-view updates
                ImageCache.shared.setImage(image, for: cacheableObject)

                cachedImage = image
            }
        } catch {
            // Keep showing monogram on error
            Logger.error("Error loading image cacheable object: \(cacheableObject) from url: \(imageURL)")
            cachedImage = nil
        }

        isLoading = false
    }
}

struct ProfileAvatarView: View {
    let profile: Profile

    var body: some View {
        AvatarView(
            imageURL: profile.avatarURL,
            fallbackName: profile.displayName,
            cacheableObject: profile
        )
    }
}

struct ConversationAvatarView: View {
    let conversation: Conversation

    var body: some View {
        if conversation.imageURL != nil {
            // Fall back to URL-based loading with conversation object for cache awareness
            AvatarView(
                imageURL: conversation.imageURL,
                fallbackName: conversation.name ?? "Untitled",
                cacheableObject: conversation
            )
        } else {
            MonogramView(text: "")
        }
    }
}

#Preview {
    @Previewable @State var profileImage: UIImage?
    let profile: Profile = .mock(name: "John Doe")
    ProfileAvatarView(profile: profile)
}

#Preview {
    @Previewable @State var conversationImage: UIImage?
    let conversation = Conversation.mock(members: [.mock(), .mock()])
    ConversationAvatarView(conversation: conversation)
}

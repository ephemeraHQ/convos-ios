import ConvosCore
import SwiftUI
import UIKit

class MessageInviteCell: UICollectionViewCell {
    private var messageType: MessageSource = .incoming
    private var longPressGestureRecognizer: UILongPressGestureRecognizer?
    private var panGestureRecognizer: UIPanGestureRecognizer?
    private var doubleTapGestureRecognizer: UITapGestureRecognizer?

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        self.contentConfiguration = nil
        messageType = .incoming
    }

    func setup(
        invite: MessageInvite,
        messageType: MessageSource,
        style: MessagesCollectionCell.BubbleType,
        profile: Profile,
        onTapInvite: @escaping ((MessageInvite) -> Void),
        onTapAvatar: (() -> Void)?
    ) {
        self.messageType = messageType
        contentConfiguration = UIHostingConfiguration {
            VStack(alignment: .leading) {
                MessageInviteContainerView(
                    invite: invite,
                    style: style,
                    isOutgoing: messageType == .outgoing,
                    profile: profile,
                    onTapInvite: onTapInvite,
                    onTapAvatar: onTapAvatar
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .margins(.top, DesignConstants.Spacing.stepX)
        .margins(.bottom, 0.0)
    }

    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutAttributes {
        layoutAttributesForHorizontalFittingRequired(layoutAttributes)
    }
}

struct MessageInviteContainerView: View {
    let invite: MessageInvite
    let style: MessagesCollectionCell.BubbleType
    let isOutgoing: Bool
    let profile: Profile
    let onTapInvite: ((MessageInvite) -> Void)
    let onTapAvatar: (() -> Void)?

    private var textColor: Color {
        // Match the text color based on message type (same as MessageContainer)
        if isOutgoing {
            return Color.colorTextPrimaryInverted
        } else {
            return Color.colorTextPrimary
        }
    }

    var body: some View {
        HStack {
            MessageContainer(style: style, isOutgoing: isOutgoing) {
                MessageInviteView(invite: invite)
                    .onTapGesture {
                        onTapInvite(invite)
                    }
            } avatarView: {
                Group {
                    if isOutgoing {
                        EmptyView()
                    } else {
                        if style == .normal {
                            Spacer()
                        } else {
                            ProfileAvatarView(profile: profile, profileImage: nil)
                        }
                    }
                }
            } onTapAvatar: {
                onTapAvatar?()
            }
        }
    }
}

#Preview {
    ScrollView {
        VStack {
            MessageInviteContainerView(
                invite: .mock,
                style: .normal,
                isOutgoing: false,
                profile: .mock(),
                onTapInvite: { _ in
                },
                onTapAvatar: {
                })
            MessageInviteContainerView(
                invite: .mock,
                style: .tailed,
                isOutgoing: true,
                profile: .mock(),
                onTapInvite: { _ in
                },
                onTapAvatar: {})
            MessageInviteContainerView(
                invite: .empty,
                style: .normal,
                isOutgoing: false,
                profile: .mock(),
                onTapInvite: { _ in
                },
                onTapAvatar: {
                })
            MessageInviteContainerView(
                invite: .empty,
                style: .tailed,
                isOutgoing: true,
                profile: .mock(),
                onTapInvite: { _ in
                },
                onTapAvatar: {})
        }
        .padding(.horizontal, DesignConstants.Spacing.step2x)
    }
}

struct MessageInviteView: View {
    let invite: MessageInvite
    @State private var cachedImage: UIImage?

    var title: String {
        if let name = invite.conversationName, !name.isEmpty {
            return "Pop into my convo \"\(name)\""
        }
        return "Pop into my convo before it explodes"
    }

    var description: String {
        if let description = invite.conversationDescription, !description.isEmpty {
            return description
        }
        return "convos.org"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0.0) {
            ZStack {
                Image("convosIconLarge")
                    .resizable()
                    .tint(.colorTextPrimaryInverted)
                    .foregroundStyle(.colorTextPrimaryInverted)
                    .frame(width: 96.0, height: 96.0)
                    .padding(.vertical, DesignConstants.Spacing.step12x)

                if let image = cachedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .aspectRatio(contentMode: .fill)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 120.0)
            .background(.colorBackgroundInverted)

            VStack(alignment: .leading, spacing: 2.0) {
                Text(title)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .truncationMode(.tail)
                    .foregroundStyle(.black)
                    .multilineTextAlignment(.leading)
                    .font(.body)
                    .fontWeight(.bold)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.colorTextSecondary)
            }
            .padding(.vertical, DesignConstants.Spacing.step3x)
            .padding(.horizontal, DesignConstants.Spacing.step4x)
        }
        .background(.colorLinkBackground)
        .frame(maxWidth: 250.0)
        .cachedImage(for: invite) { image in
            cachedImage = image
        }
        .task {
            guard let imageURL = invite.imageURL else {
                return
            }

            do {
                let (data, _) = try await URLSession.shared.data(from: imageURL)
                if let image = UIImage(data: data) {
                    // Cache the image for future use
                    ImageCache.shared.setImage(image, for: invite)
                    cachedImage = image
                }
            } catch {
                Log.error("Error loading image for invite")
                cachedImage = nil
            }
        }
    }
}

#Preview {
    MessageInviteView(invite: .mock)
        .frame(width: 200.0)
}

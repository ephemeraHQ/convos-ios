import SwiftUI

struct ContactCardView: View {
    let contactCard: ContactCard
    let avatarSize: CGFloat = 40.0
    @State var identifier: String = "testing-string"

    private func text(title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 2.0) {
            Text(title)
                .font(.body).fontWeight(.medium)
            Text(description)
                .font(.caption)
        }
        .foregroundStyle(.white)
    }

    static var maxWidth: CGFloat {
        380.0
    }

    var body: some View {
        VStack(spacing: 0.0) {
            HStack {
                switch contactCard.type {
                case .standard(let inbox):
                    ProfileAvatarView(profile: inbox.profile)
                        .frame(width: avatarSize, height: avatarSize)

                    text(
                        title: inbox.profile.displayName,
                        description: inbox.profile.username
                    )
                case .ephemeral:
                    Circle()
                        .fill(.white.opacity(0.1))
                        .frame(width: avatarSize, height: avatarSize)

                    text(
                        title: "OTR™",
                        description: "Real life is off the record"
                    )
                case .cash:
                    Circle()
                        .fill(.white.opacity(0.1))
                        .frame(width: avatarSize, height: avatarSize)

                    text(
                        title: "Cash",
                        description: "Your private account"
                    )
                }

                Spacer()

                contactCard.iconImage
                    .frame(width: avatarSize, height: avatarSize)
            }
            .padding(DesignConstants.Spacing.step8x)

            VStack(spacing: 20.0) {
                QRCodeView(identifier: $identifier, backgroundColor: contactCard.color, foregroundColor: .white)
            }
            .aspectRatio(1.0, contentMode: .fit)
            .padding(.horizontal, DesignConstants.Spacing.step8x)
            .padding(.bottom, DesignConstants.Spacing.step8x)
        }
        .frame(maxWidth: Self.maxWidth)
        .background(contactCard.color)
        .clipShape(RoundedRectangle(cornerRadius: DesignConstants.CornerRadius.large))
        .shadow(color: .colorDarkAlpha15, radius: 20, x: 0, y: -16)
        .overlay(
            RoundedRectangle(cornerRadius: DesignConstants.CornerRadius.large)
                .inset(by: 0.5)
                .stroke(.white.opacity(0.15), lineWidth: 1)
        )
    }
}

#Preview {
    ScrollView {
        VStack {
            ContactCardView(contactCard: .mock())

            ContactCardView(contactCard: .mock(type: .ephemeral([.mock(type: .ephemeral)])))

            ContactCardView(contactCard: .mock(type: .cash([.mock(type: .standard)])))
        }
    }
}

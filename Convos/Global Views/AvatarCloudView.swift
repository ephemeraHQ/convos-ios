import SwiftUI

struct BubbleCloudLayout: Layout {
    var spacing: CGFloat = 4
    struct CacheKey: Hashable {
        let count: Int
        let base: CGFloat
    }
    typealias Cache = [CacheKey: [(offset: CGSize, size: CGFloat)]]

    func makeCache(subviews: Subviews) -> Cache {
        return [:]
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let defaultSize = CGSize(width: 140, height: 140)
        return CGSize(width: proposal.width ?? defaultSize.width,
                      height: proposal.height ?? defaultSize.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let count = subviews.count
        let base = min(bounds.width, bounds.height)

        let key = CacheKey(count: count, base: base)
        let layout: [(offset: CGSize, size: CGFloat)]
        if let cached = cache[key] {
            layout = cached
        } else {
            let computed = self.layout(for: count, base: base)
            cache[key] = computed
            layout = computed
        }

        for (i, subview) in subviews.enumerated() {
            guard let layoutItem = i < layout.count ? layout[i] : layout.last else {
                return
            }
            let size = CGSize(width: layoutItem.size, height: layoutItem.size)
            let origin = CGPoint(
                x: center.x + layoutItem.offset.width - size.width / 2,
                y: center.y + layoutItem.offset.height - size.height / 2
            )
            subview.place(at: origin, proposal: ProposedViewSize(size))
        }
    }

    func layout(for count: Int, base: CGFloat) -> [(offset: CGSize, size: CGFloat)] {
        switch count {
        case 2:
            return [
                (.init(width: -base * 0.15, height: -base * 0.15), base * 0.43),
                (.init(width: base * 0.15, height: base * 0.15), base * 0.32)
            ]
        case 3:
            return [
                (.init(width: -base * 0.2, height: -base * 0.125), base * 0.35),
                (.init(width: base * 0.2, height: -base * 0.125), base * 0.35),
                (.init(width: 0, height: base * 0.25), base * 0.35)
            ]
        case 4:
            return [
                (.init(width: -base * 0.18, height: -base * 0.18), base * 0.34),
                (.init(width: base * 0.18, height: -base * 0.18), base * 0.34),
                (.init(width: -base * 0.18, height: base * 0.18), base * 0.34),
                (.init(width: base * 0.18, height: base * 0.18), base * 0.34)
            ]
        case 5:
            return [
                (.init(width: 0, height: -base * 0.3), base * 0.3),
                (.init(width: -base * 0.28, height: -base * 0.1), base * 0.3),
                (.init(width: base * 0.28, height: -base * 0.1), base * 0.3),
                (.init(width: -base * 0.18, height: base * 0.22), base * 0.3),
                (.init(width: base * 0.18, height: base * 0.22), base * 0.3)
            ]
        case 6:
            return (0..<6).map {
                let angle = CGFloat($0) / 6 * 2 * .pi
                let radius = base * 0.3
                let offset = CGSize(width: cos(angle) * radius, height: sin(angle) * radius)
                return (offset, base * 0.28)
            }
        default:
            // 7+
            return (0..<7).map {
                if $0 == 0 {
                    return (.zero, base * 0.25)
                }
                let angle = CGFloat($0) / 6 * 2 * .pi
                let radius = base * 0.3
                let offset = CGSize(width: cos(angle) * radius, height: sin(angle) * radius)
                return (offset, base * 0.25)
            }
        }
    }
}

struct AvatarCloudView: View {
    let avatars: [AvatarData]
    private let visibleAvatars: [AvatarData]
    let maxVisible: Int = 7

    init(avatars: [AvatarData]) {
        self.avatars = avatars
        self.visibleAvatars = Array(avatars.prefix(maxVisible))
    }

    var overflowCount: Int {
        max(0, avatars.count - maxVisible)
    }

    var body: some View {
        if avatars.isEmpty {
            MonogramView(text: "")
        } else if avatars.count == 1, let avatar = avatars.first {
            AvatarView(
                imageURL: avatar.imageURL,
                fallbackName: avatar.fallbackName
            )
        } else {
            BubbleCloudLayout(spacing: 6) {
                ForEach(visibleAvatars) { avatar in
                    AvatarView(imageURL: avatar.imageURL, fallbackName: avatar.fallbackName)
                }

                if overflowCount > 0 {
                    MonogramView(text: "\(overflowCount)+")
                }
            }
            .background(.colorBorderSubtle2)
            .aspectRatio(1.0, contentMode: .fit)
            .mask(Circle())
        }
    }
}

struct AvatarData: Identifiable, Equatable {
    let id: String
    let imageURL: URL?
    let fallbackName: String
}

#Preview {
    let avatarSize: CGFloat = 90.0

    ScrollView {
        VStack(spacing: 10.0) {
            AvatarCloudView(avatars: [
                AvatarData(id: "1", imageURL: nil, fallbackName: "Alice Smith")
            ])
            .frame(width: avatarSize, height: avatarSize)

            AvatarCloudView(avatars: [
                AvatarData(id: "1", imageURL: nil, fallbackName: "Alice Smith"),
                AvatarData(id: "2", imageURL: nil, fallbackName: "Bob Johnson"),
            ])
            .frame(width: avatarSize, height: avatarSize)

            AvatarCloudView(avatars: [
                AvatarData(id: "1", imageURL: nil, fallbackName: "Alice Smith"),
                AvatarData(id: "2", imageURL: nil, fallbackName: "Bob Johnson"),
                AvatarData(id: "3", imageURL: nil, fallbackName: "Charlie Brown")
            ])
            .frame(width: avatarSize, height: avatarSize)

            AvatarCloudView(avatars: [
                AvatarData(id: "1", imageURL: nil, fallbackName: "Alice Smith"),
                AvatarData(id: "2", imageURL: nil, fallbackName: "Bob Johnson"),
                AvatarData(id: "3", imageURL: nil, fallbackName: "Charlie Brown"),
                AvatarData(id: "4", imageURL: nil, fallbackName: "Diana Prince")
            ])
            .frame(width: avatarSize, height: avatarSize)

            AvatarCloudView(avatars: [
                AvatarData(id: "1", imageURL: nil, fallbackName: "Alice Smith"),
                AvatarData(id: "2", imageURL: nil, fallbackName: "Bob Johnson"),
                AvatarData(id: "3", imageURL: nil, fallbackName: "Charlie Brown"),
                AvatarData(id: "4", imageURL: nil, fallbackName: "Diana Prince"),
                AvatarData(id: "5", imageURL: nil, fallbackName: "Evan Wright")
            ])
            .frame(width: avatarSize, height: avatarSize)

            AvatarCloudView(avatars: [
                AvatarData(id: "1", imageURL: nil, fallbackName: "Alice Smith"),
                AvatarData(id: "2", imageURL: nil, fallbackName: "Bob Johnson"),
                AvatarData(id: "3", imageURL: nil, fallbackName: "Charlie Brown"),
                AvatarData(id: "4", imageURL: nil, fallbackName: "Diana Prince"),
                AvatarData(id: "5", imageURL: nil, fallbackName: "Evan Wright"),
                AvatarData(id: "6", imageURL: nil, fallbackName: "Frank Moore")
            ])
            .frame(width: avatarSize, height: avatarSize)

            AvatarCloudView(avatars: [
                AvatarData(id: "1", imageURL: nil, fallbackName: "Alice Smith"),
                AvatarData(id: "2", imageURL: nil, fallbackName: "Bob Johnson"),
                AvatarData(id: "3", imageURL: nil, fallbackName: "Charlie Brown"),
                AvatarData(id: "4", imageURL: nil, fallbackName: "Diana Prince"),
                AvatarData(id: "5", imageURL: nil, fallbackName: "Evan Wright"),
                AvatarData(id: "6", imageURL: nil, fallbackName: "Frank Moore"),
                AvatarData(id: "7", imageURL: nil, fallbackName: "Grace Lee"),
                AvatarData(id: "8", imageURL: nil, fallbackName: "John Smith")
            ])
            .frame(width: avatarSize, height: avatarSize)

            AvatarCloudView(avatars: [
                AvatarData(id: "1", imageURL: nil, fallbackName: "Alice Smith"),
                AvatarData(id: "2", imageURL: nil, fallbackName: "Bob Johnson"),
                AvatarData(id: "3", imageURL: nil, fallbackName: "Charlie Brown"),
                AvatarData(id: "4", imageURL: nil, fallbackName: "Diana Prince"),
                AvatarData(id: "5", imageURL: nil, fallbackName: "Evan Wright"),
                AvatarData(id: "6", imageURL: nil, fallbackName: "Frank Moore"),
                AvatarData(id: "7", imageURL: nil, fallbackName: "Grace Lee"),
                AvatarData(id: "8", imageURL: nil, fallbackName: "John Smith"),
                AvatarData(id: "9", imageURL: nil, fallbackName: "Frank Wright"),
                AvatarData(id: "10", imageURL: nil, fallbackName: "Bob Jones")
            ])
            .frame(width: avatarSize, height: avatarSize)
        }
        .frame(maxWidth: .infinity)
    }
}

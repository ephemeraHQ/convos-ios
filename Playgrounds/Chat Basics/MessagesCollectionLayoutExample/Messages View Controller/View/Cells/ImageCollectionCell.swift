import SwiftUI
import UIKit

class ImageCollectionCell: UICollectionViewCell {
    func setup(with source: ImageSource, messageId: UUID, isOutgoing: Bool) {
        contentConfiguration = UIHostingConfiguration {
            ImageMessageView(source: source, messageId: messageId, isOutgoing: isOutgoing)
        }
        .margins(.vertical, 0.0)
    }

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        layoutAttributesForHorizontalFittingRequired(layoutAttributes)
    }

}

struct ImageMessageView: View {
    let source: ImageSource
    let messageId: UUID
    let isOutgoing: Bool
    let minHeight: CGFloat = 120.0

    var image: some View {
        Group {
            switch source {
                case .image(let uiImage):
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                case .imageURL(let url):
                    AsyncImage(url: url) { phase in
                        switch phase {
                            case .empty:
                                HStack {
                                    Spacer()
                                    ProgressView()
                                    Spacer()
                                }
                                .frame(minHeight: minHeight)
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                            case .failure:
                                Image(systemName: "photo")
                                    .frame(minHeight: minHeight)
                            @unknown default:
                                EmptyView()
                                    .frame(minHeight: minHeight)
                        }
                    }
            }
        }
    }

    var body: some View {
        MessageContainer(style: .normal,
                         isOutgoing: isOutgoing) {
            image
        }
    }
}

#Preview {
    let url = URL(string: "https://upload.wikimedia.org/wikipedia/commons/thumb/2/21/William_Shakespeare_by_John_Taylor%2C_edited.jpg/1920px-William_Shakespeare_by_John_Taylor%2C_edited.jpg")!
    return ImageMessageView(source: .imageURL(url), messageId: UUID(), isOutgoing: false)
}

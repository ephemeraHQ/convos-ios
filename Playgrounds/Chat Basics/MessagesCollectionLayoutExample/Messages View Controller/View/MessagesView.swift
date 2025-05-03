import SwiftUI

struct MessagesView: UIViewControllerRepresentable {
    let imagesEnabled: Bool

    func makeUIViewController(context: Context) -> MessagesViewController {
        return MessagesViewControllerBuilder.build(enableImages: imagesEnabled)
    }

    func updateUIViewController(_ uiViewController: MessagesViewController, context: Context) {
    }
}

#Preview {
    MessagesView(imagesEnabled: true)
        .ignoresSafeArea()
}

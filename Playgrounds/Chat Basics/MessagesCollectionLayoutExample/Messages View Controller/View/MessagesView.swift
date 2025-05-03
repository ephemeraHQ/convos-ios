import SwiftUI

struct MessagesView: UIViewControllerRepresentable {

    func makeUIViewController(context: Context) -> MessagesViewController {
        return MessagesViewControllerBuilder.build()
    }

    func updateUIViewController(_ uiViewController: MessagesViewController, context: Context) {
    }
}

#Preview {
    MessagesView()
        .ignoresSafeArea()
}

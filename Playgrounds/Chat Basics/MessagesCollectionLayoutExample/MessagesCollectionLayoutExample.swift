import SwiftUI

@main
struct MessagesCollectionLayoutExample: App {
    var body: some Scene {
        WindowGroup {
            MessagesView(imagesEnabled: false)
                .navigationBarHidden(true)
                .ignoresSafeArea()
        }
    }
}

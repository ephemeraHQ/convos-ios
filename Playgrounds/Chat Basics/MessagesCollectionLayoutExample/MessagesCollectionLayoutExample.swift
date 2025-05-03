import SwiftUI

@main
struct MessagesCollectionLayoutExample: App {
    var body: some Scene {
        WindowGroup {
            MessagesView()
                .navigationBarHidden(true)
                .ignoresSafeArea()
        }
    }
}

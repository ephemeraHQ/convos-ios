import SwiftUI

struct ConversationsView: View {
    let convos: ConvosSDK.Convos
    var body: some View {
        VStack {
            Spacer()

            Button("Sign out") {
                Task {
                    try? await convos.signOut()
                }
            }
            .convosButtonStyle(.text)

            Spacer()
        }
    }
}

#Preview {
    ConversationsView(convos: .mock)
}

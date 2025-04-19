import SwiftUI

struct ConversationsView: View {
    let authService: AuthServiceProtocol
    var body: some View {
        VStack {
            Spacer()

            Button("Sign out") {
                Task {
                    try? await authService.signOut()
                }
            }
            .convosButtonStyle(.text)

            Spacer()
        }
    }
}

#Preview {
    ConversationsView(authService: MockAuthService())
}

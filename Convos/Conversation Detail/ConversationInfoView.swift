import SwiftUI

struct ConversationInfoView: View {
    @Environment(\.dismiss) private var dismiss: DismissAction

    var body: some View {
        VStack(spacing: 0) {
            CustomToolbarView(onBack: { dismiss() }, rightContent: {
                // Add right-side buttons here
            })

            // Content
            VStack {
                Text("Conversation Info")
                    .font(.largeTitle)
                    .padding()
                Spacer()
            }
        }
        .navigationBarHidden(true)
    }
}

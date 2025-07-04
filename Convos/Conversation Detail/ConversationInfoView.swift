import SwiftUI

struct ConversationInfoView: View {
    @Environment(\.dismiss) private var dismiss: DismissAction

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack {
                    Text("Conversation Info")
                        .font(.largeTitle)
                        .padding()
                    Spacer()
                }
            }
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) {
                        dismiss()
                    }
                }
            }
        }
    }
}

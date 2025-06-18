import SwiftUI

struct ConversationInfoView: View {
    var body: some View {
        VStack {
            Text("Conversation Info")
                .font(.largeTitle)
                .padding()
            Spacer()
        }
        .navigationTitle("Info")
        .navigationBarTitleDisplayMode(.inline)
    }
}

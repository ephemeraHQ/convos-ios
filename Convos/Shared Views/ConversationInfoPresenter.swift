import SwiftUI

struct ConversationInfoPresenter<Content: View>: View {
    @ViewBuilder let content: () -> Content
//    @Bindable var conversationViewModel: ConversationViewModel

    var body: some View {
        ZStack {
            content()

            VStack {

                Spacer()
            }
        }
    }
}

#Preview {
    ConversationInfoPresenter {
        NavigationStack {
            
        }
    }
}

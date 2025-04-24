import Combine
import SwiftUI

extension ConvosSDK.MessagingServiceState {
    var displaystring: String {
        switch self {
        case .uninitialized:
            return "Uninitialized"
        case .initializing:
            return "Initializing..."
        case .ready:
            return "Ready!"
        case .authorizing:
            return "Authorizing..."
        case .stopping:
            return "Stopping..."
        case .error(let error):
            return "Error: \(error)"
        }
    }
}

struct ConversationsView: View {
    @State var viewModel: ConversationsViewModel

    init(convos: ConvosSDK.Convos) {
        _viewModel = State(initialValue: .init(convos: convos))
    }

    var body: some View {
        VStack {
            Spacer()

            Button("Sign out") {
                viewModel.signOut()
            }
            .convosButtonStyle(.text)

            Spacer()

            Text(viewModel.messagingState.displaystring)
                .font(.subheadline)
                .foregroundStyle(.colorTextSecondary)
                .multilineTextAlignment(.center)
        }
    }
}

#Preview {
    ConversationsView(convos: .mock)
}

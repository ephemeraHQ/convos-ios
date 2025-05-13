import SwiftUI

struct RootView: View {
    private let convos: ConvosSDK.Convos
    private let analyticsService: AnalyticsServiceProtocol
    private let identityStore: CTIdentityStore = CTIdentityStore()
    private let conversationStore: CTConversationStore = CTConversationStore()

    @State var viewModel: AppViewModel

    init(convos: ConvosSDK.Convos,
         analyticsService: AnalyticsServiceProtocol) {
        self.convos = convos
        self.analyticsService = analyticsService
        _viewModel = .init(initialValue: .init(convos: convos))
    }

    var body: some View {
        switch viewModel.appState {
        case .loading:
            VStack {
                Spacer()
                AppVersionView()
                Spacer()
            }
        case .signedIn:
            ChatListView(conversationStore: conversationStore,
                         identityStore: identityStore)
        case .signedOut:
            OnboardingView(convos: convos)
        }
    }
}

#Preview {
    RootView(convos: .mock, analyticsService: MockAnalyticsService())
}

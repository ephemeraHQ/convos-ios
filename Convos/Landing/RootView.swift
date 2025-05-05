import Foundation
import GRDB
import SwiftUI

struct RootView: View {
    private let authService: AuthServiceProtocol
    private let analyticsService: AnalyticsServiceProtocol

    @State var viewModel: AppViewModel

    init(authService: AuthServiceProtocol, analyticsService: AnalyticsServiceProtocol) {
        self.authService = authService
        self.analyticsService = analyticsService
        _viewModel = State(initialValue: AppViewModel(authService: authService))
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
            Group {
                // swiftlint:disable:next force_try
                let identityStore = try! CTIdentityStore()
                let conversationStore = CTConversationStore()
                ChatListView(
                    conversationStore: conversationStore,
                    identityStore: identityStore
                )
            }
        case .signedOut:
            OnboardingView(authService: authService)
        }
    }
}

#Preview {
    RootView(authService: MockAuthService(),
             analyticsService: MockAnalyticsService())
}

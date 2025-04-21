import SwiftUI

struct RootView: View {
    private let authService: AuthServiceProtocol
    private let analyticsService: AnalyticsServiceProtocol
    
    @State var viewModel: AppViewModel
    
    init(authService: AuthServiceProtocol, analyticsService: AnalyticsServiceProtocol) {
        self.authService = authService
        self.analyticsService = analyticsService
        _viewModel = .init(initialValue: .init(authService: authService))
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
            ConversationsView(authService: authService)
        case .signedOut:
            OnboardingView(authService: authService)
        }
    }
}

#Preview {
    RootView(authService: MockAuthService(),
             analyticsService: MockAnalyticsService())
}

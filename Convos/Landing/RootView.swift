import SwiftUI

struct RootView: View {
    private let authService: AuthServiceProtocol

    @State var viewModel: AppViewModel

    init(authService: AuthServiceProtocol) {
        self.authService = authService
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
    RootView(authService: MockAuthService())
}

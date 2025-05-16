import SwiftUI

struct RootView: View {
    private let convos: ConvosSDK.Convos
    private let analyticsService: AnalyticsServiceProtocol
    private let identityStore: CTIdentityStore = CTIdentityStore()
    private let userRepository: UserRepositoryProtocol

    @State var viewModel: AppViewModel

    init(convos: ConvosSDK.Convos,
         analyticsService: AnalyticsServiceProtocol) {
        self.convos = convos
        self.analyticsService = analyticsService
        self.userRepository = UserRepository(dbReader: convos.databaseReader)
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
            ChatListView(messagingService: convos.messaging,
                         userRepository: userRepository)
        case .signedOut:
            OnboardingView(convos: convos)
        }
    }
}

//#Preview {
//    RootView(convos: .mock, analyticsService: MockAnalyticsService())
//}

import SwiftUI

struct RootView: View {
    private let convos: ConvosClient
    private let analyticsService: AnalyticsServiceProtocol
    private let userRepository: UserRepositoryProtocol
    private let conversationsRepository: ConversationsRepositoryProtocol

    @State var messagingService: MessagingServiceObservable
    @State var viewModel: AppViewModel

    init(convos: ConvosClient,
         analyticsService: AnalyticsServiceProtocol) {
        self.convos = convos
        self.analyticsService = analyticsService
        self.userRepository = convos.messaging.userRepository()
        self.conversationsRepository = convos.messaging.conversationsRepository(for: .allowed)
        self.messagingService = .init(messagingService: convos.messaging)
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
            ConversationsListView(
                convos: convos,
                userRepository: userRepository,
                conversationsRepository: conversationsRepository
            )
            .environment(messagingService)
        case .signedOut:
            OnboardingView(convos: convos)
        }
    }
}

 #Preview {
     RootView(convos: .mock(),
              analyticsService: MockAnalyticsService())
 }

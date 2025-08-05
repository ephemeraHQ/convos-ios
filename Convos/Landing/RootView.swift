import SwiftUI

struct RootView: View {
    private let convos: ConvosClient
    private let analyticsService: AnalyticsServiceProtocol

    @State var viewModel: AppViewModel

    @State var conversationViewModel: ConversationViewModel = .init()

    init(convos: ConvosClient,
         analyticsService: AnalyticsServiceProtocol) {
        self.convos = convos
        self.analyticsService = analyticsService
        _viewModel = .init(initialValue: .init(convos: convos))
    }

    var body: some View {
//        ConversationsView(session: convos.session)
        ConversationView(viewModel: conversationViewModel)
    }
}

 #Preview {
     RootView(convos: .mock(),
              analyticsService: MockAnalyticsService())
 }

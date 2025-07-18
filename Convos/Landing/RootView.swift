import SwiftUI

struct RootView: View {
    private let convos: ConvosClient
    private let analyticsService: AnalyticsServiceProtocol

    @State var viewModel: AppViewModel

    init(convos: ConvosClient,
         analyticsService: AnalyticsServiceProtocol) {
        self.convos = convos
        self.analyticsService = analyticsService
        _viewModel = .init(initialValue: .init(convos: convos))
    }

    var body: some View {
        switch viewModel.appState {
        case .loading:
            EmptyView()
        case .ready:
            ConversationsView(session: convos.session)
        }
    }
}

 #Preview {
     RootView(convos: .mock(),
              analyticsService: MockAnalyticsService())
 }

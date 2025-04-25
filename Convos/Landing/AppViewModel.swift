import Combine
import SwiftUI

@MainActor
@Observable
final class AppViewModel {
    enum AppState {
        case signedIn, signedOut, loading
    }

    let convos: ConvosSDK.Convos
    private var cancellables: Set<AnyCancellable> = .init()

    private(set) var appState: AppState = .loading

    init(convos: ConvosSDK.Convos) {
        self.convos = convos

        Task {
            await convos.prepare()
            observeAuthState()
        }
    }

    private func observeAuthState() {
        convos.authState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] authState in
                guard let self else { return }
                switch authState {
                case .authorized:
                    self.appState = .signedIn
                case .unauthorized:
                    self.appState = .signedOut
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }
}

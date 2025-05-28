import Combine
import SwiftUI

@MainActor
@Observable
final class AppViewModel {
    enum AppState {
        case signedIn, signedOut, loading
    }

    let convos: ConvosClient
    private var cancellables: Set<AnyCancellable> = .init()

    private(set) var appState: AppState = .loading

    init(convos: ConvosClient) {
        self.convos = convos

        Task {
            do {
                try await convos.prepare()
            } catch {
                Logger.error("Convos SDK failed preparing: \(error.localizedDescription)")
            }
            observeAuthState()
        }
    }

    private func observeAuthState() {
        convos.authState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] authState in
                guard let self else { return }
                switch authState {
                case .authorized, .registered:
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

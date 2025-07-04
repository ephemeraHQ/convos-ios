import Combine
import SwiftUI

@MainActor
@Observable
final class AppViewModel {
    enum AppState {
        case signedIn, signedOut, migrating, loading
    }

    let convos: ConvosClient
    private var cancellables: Set<AnyCancellable> = .init()

    private(set) var appState: AppState = .loading

    init(convos: ConvosClient) {
        self.convos = convos

        do {
            try convos.prepare()
        } catch {
            Logger.error("Convos SDK failed preparing: \(error.localizedDescription)")
        }
        observeAuthState()
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
                case .migrating:
                    self.appState = .migrating
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }
}

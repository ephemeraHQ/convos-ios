import Combine
import SwiftUI

@Observable
final class AppViewModel {
    enum AppState {
        case signedIn, signedOut, loading
    }

    let authService: AuthServiceProtocol
    private var cancellables: Set<AnyCancellable> = .init()

    private(set) var appState: AppState = .loading

    init(authService: AuthServiceProtocol = PrivyAuthService()) {
        self.authService = authService
        observeAuthState()
    }

    private func observeAuthState() {
        authService.authStatePublisher()
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

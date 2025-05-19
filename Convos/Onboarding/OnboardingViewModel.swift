import Combine
import SwiftUI

@Observable
final class OnboardingViewModel {
    let convos: ConvosSDK.Convos
    private var cancellables: Set<AnyCancellable> = .init()
    var name: String = "" {
        didSet {
            validateName()
        }
    }

    let authAllowsSignIn: Bool
    var imageState: ContactCardImage.State = .empty
    var nameIsValid: Bool = false
    var nameError: String?
    var isEditingContactCard: Bool = true
    var authenticationError: String?
    var isAuthorized: Bool = false
    private let minimumNameLength: Int = 3

    init(convos: ConvosSDK.Convos) {
        self.convos = convos
        self.authAllowsSignIn = convos.supportsMultipleAccounts
        observeAuthState()
    }

    // MARK: - Public

    func signIn() {
        Task {
            do {
                try await convos.signIn()
            } catch {
                Logger.error("Error signing in: \(error)")
                authenticationError = error.localizedDescription
            }
        }
    }

    func createContactCard() {
        isEditingContactCard = false
        Task {
            do {
                try await convos.register(displayName: name)
            } catch {
                Logger.error("Error registering display name: \(name) error: \(error)")
                authenticationError = error.localizedDescription
                isEditingContactCard = true
            }
        }
    }

    // MARK: - Private

    private func observeAuthState() {
        convos.authState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] authState in
                guard let self else { return }
                switch authState {
                case .authorized, .registered:
                    self.isAuthorized = true
                case .unauthorized:
                    self.isAuthorized = false
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }

    func validateName() {
        let allowed = CharacterSet.alphanumerics.union(.whitespaces)
        let nameContainsOnlyLettersSpacesAndNumbers = name.unicodeScalars.allSatisfy { allowed.contains($0) }
        if !nameContainsOnlyLettersSpacesAndNumbers {
            nameError = "Letters, numbers and spaces only"
        } else {
            nameError = nil
        }
        nameIsValid = (!name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                       nameContainsOnlyLettersSpacesAndNumbers &&
                       name.count >= minimumNameLength)
    }
}

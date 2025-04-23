import SwiftUI

@Observable
final class OnboardingViewModel {
    let convos: ConvosSDK.Convos
    var name: String = "" {
        didSet {
            validateName()
        }
    }

    var imageState: ContactCardImage.State = .empty
    var nameIsValid: Bool = false
    var nameError: String?

    init(convos: ConvosSDK.Convos) {
        self.convos = convos
    }

    // MARK: - Public

    func signIn() {
        Task {
            do {
                try await convos.signIn()
            } catch {
                Logger.error("Error signing in: \(error)")
            }
        }
    }

    func createContactCard() {
        Task {
            do {
                try await convos.register(displayName: name)
            } catch {
                Logger.error("Error registering display name: \(name) error: \(error)")
            }
        }
    }

    // MARK: - Private

    func validateName() {
        let allowed = CharacterSet.alphanumerics.union(.whitespaces)
        let nameContainsOnlyLettersSpacesAndNumbers = name.unicodeScalars.allSatisfy { allowed.contains($0) }
        if !nameContainsOnlyLettersSpacesAndNumbers {
            nameError = "Letters, numbers and spaces only"
        } else {
            nameError = nil
        }
        nameIsValid = (!name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            nameContainsOnlyLettersSpacesAndNumbers)
    }
}

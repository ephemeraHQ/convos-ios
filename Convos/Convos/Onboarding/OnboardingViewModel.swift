//
//  OnboardingViewModel.swift
//  Convos
//
//  Created by Jarod Luebbert on 4/16/25.
//

import SwiftUI

@Observable
final class OnboardingViewModel {
    let authService: AuthServiceProtocol
    var name: String = "" {
        didSet {
            validateName()
        }
    }
    var imageState: ContactCardImage.State = .empty
    var nameIsValid: Bool = false
    var nameError: String? = nil
    
    init(authService: AuthServiceProtocol) {
        self.authService = authService
    }
    
    // MARK: - Public
    
    func signIn() {
        Task {
            do {
                try await authService.signIn()
            } catch {
                print("Error signing in: \(error)")
            }
        }
    }
    
    func createContactCard() {
        signIn()
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

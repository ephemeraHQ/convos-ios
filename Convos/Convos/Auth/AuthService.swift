//
//  AuthService.swift
//  Convos
//
//  Created by Jarod Luebbert on 4/16/25.
//

import Foundation
import Combine

enum AuthState {
    case unknown, authorized, unauthorized
}

protocol AuthServiceProtocol {
    
    var state: AuthState { get }
    
    func signIn() async throws
    func signOut() async throws
    
    func authStatePublisher() -> AnyPublisher<AuthState, Never>
}

class AuthService: AuthServiceProtocol {
    
    var state: AuthState {
        authStateSubject.value
    }
    
    private var authStateSubject: CurrentValueSubject<AuthState, Never> = .init(.unknown)
    
    init() {
        authStateSubject.send(.unauthorized)
    }
    
    func signIn() async throws {
        authStateSubject.send(.authorized)
    }
    
    func signOut() async throws {
        authStateSubject.send(.unauthorized)
    }
    
    func authStatePublisher() -> AnyPublisher<AuthState, Never> {
        return authStateSubject.eraseToAnyPublisher()
    }
}

class MockAuthService: AuthServiceProtocol {
        
    var state: AuthState {
        authStateSubject.value
    }
    
    private var authStateSubject: CurrentValueSubject<AuthState, Never> = .init(.unknown)
    
    init() {
        authStateSubject.send(.unauthorized)
    }
    
    func signIn() async throws {
        authStateSubject.send(.authorized)
    }
    
    func signOut() async throws {
        authStateSubject.send(.unauthorized)
    }
    
    func authStatePublisher() -> AnyPublisher<AuthState, Never> {
        return authStateSubject.eraseToAnyPublisher()
    }
}

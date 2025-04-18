//
//  PrivyAuthService.swift
//  Convos
//
//  Created by Jarod Luebbert on 4/17/25.
//

import Foundation
import Combine
import PrivySDK

extension AuthState {
    var authServiceState: AuthServiceState {
        switch self {
        case .authenticated:
            return .authorized
        case .unauthenticated:
            return .unauthorized
        case .notReady:
            return .unknown
        default:
            return .unknown
        }
    }
}

class PrivyAuthService: AuthServiceProtocol {
    
    var state: AuthServiceState {
        return privy.authState.authServiceState
    }
    
    let privy: Privy
    
    init() {
        let config = PrivyConfig(
            appId: Secrets.PRIVY_APP_ID,
            appClientId: Secrets.PRIVY_APP_CLIENT_ID,
            loggingConfig: .init(
                logLevel: .verbose
            )
        )

        self.privy = PrivySdk.initialize(config: config)
        
        awaitPrivySDKReady()
    }
    
    private func awaitPrivySDKReady() {
        Task {
            await privy.awaitReady()

            if case .authenticated(let privyUser) = privy.authState {
//                authStateSubject.send(.authorized)
            } else {
//                authStateSubject.send(.unauthorized)
            }
        }
    }
    
    func signIn() async throws {
    }
    
    func signOut() async throws {
    }
    
    func authStatePublisher() -> AnyPublisher<AuthServiceState, Never> {
        return privy.authStatePublisher.map { state in
            switch state {
            case .authenticated:
                return .authorized
            case .unauthenticated:
                return .unauthorized
            case .notReady:
                return .unknown
            default:
                return .unknown
            }
        }.eraseToAnyPublisher()
    }
}

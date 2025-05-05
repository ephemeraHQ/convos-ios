import AuthenticationServices
import Foundation

/// A response type that encapsulates the result of an authorization request
public enum ASAuthorizationResponse {
    case registration(ASAuthorizationPlatformPublicKeyCredentialRegistration)
    case assertion(ASAuthorizationPlatformPublicKeyCredentialAssertion)
}

/// A wrapper class around ASAuthorizationController that provides async/await functionality
public final class AsyncAuthorizationController {
    private let controller: ASAuthorizationController
    private var delegate: AsyncAuthorizationDelegate?

    public init(controller: ASAuthorizationController) {
        self.controller = controller
    }

    /// Performs authorization requests asynchronously
    /// - Returns: An ASAuthorizationResponse containing the result of the authorization
    /// - Throws: ASAuthorizationError if the authorization fails
    public func performRequests() async throws -> ASAuthorizationResponse {
        try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                let delegate = AsyncAuthorizationDelegate { result in
                    continuation.resume(with: result)
                }

                self.delegate = delegate
                self.controller.delegate = delegate
                self.controller.performRequests()
            }
        }
    }
}

@MainActor
private final class AsyncAuthorizationDelegate: NSObject, ASAuthorizationControllerDelegate {
    private let completion: (Result<ASAuthorizationResponse, Error>) -> Void

    init(completion: @escaping (Result<ASAuthorizationResponse, Error>) -> Void) {
        self.completion = completion
        super.init()
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        if let registration = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration {
            completion(.success(.registration(registration)))
        } else if let assertion = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion {
            completion(.success(.assertion(assertion)))
        } else {
            completion(.failure(ASAuthorizationError(.failed)))
        }
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        completion(.failure(error))
    }
}

import FirebaseAppCheck
import FirebaseCore
import Foundation

public enum FirebaseHelperCore {
    // AppAttest is not available in extensions - the backend will provide a token for the extension to use
    private static var overrideAppCheckToken: String?

    public static func configure(with optionsURL: URL) {
        guard let options = FirebaseOptions(contentsOfFile: optionsURL.path) else { return }
        #if targetEnvironment(simulator)
            AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        #else
            AppCheck.setAppCheckProviderFactory(AppAttestFactory())
        #endif
        FirebaseApp.configure(options: options)
        Logger.info("Firebase configured for current environment: \(FirebaseApp.app()?.options.googleAppID ?? "undefined")")
    }

    public static func getAppCheckToken(forceRefresh: Bool = false) async throws -> String {
        if let token = overrideAppCheckToken { return token }
        let result = try await AppCheck.appCheck().token(forcingRefresh: forceRefresh)
        return result.token
    }

    /// Pass nil to clear the override and resume SDK-based token fetching.
    public static func setOverrideAppCheckToken(_ token: String?) {
        overrideAppCheckToken = token
    }
}

final class AppAttestFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        AppAttestProvider(app: app)
    }
}

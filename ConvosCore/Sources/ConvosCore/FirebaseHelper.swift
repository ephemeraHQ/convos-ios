import FirebaseAppCheck
import FirebaseCore
import Foundation

public enum FirebaseHelperCore {
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
        let result = try await AppCheck.appCheck().token(forcingRefresh: forceRefresh)
        return result.token
    }
}

final class AppAttestFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        AppAttestProvider(app: app)
    }
}

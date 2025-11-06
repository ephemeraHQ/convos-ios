import ConvosCore
import Foundation
import Sentry

enum SentryConfiguration {
    static func configure() {
        guard shouldEnableSentry() else {
            Log.info("Sentry disabled: not a Convos (Dev) distribution build")
            return
        }

        let dsn = Secrets.SENTRY_DSN
        guard !dsn.isEmpty else {
            Log.error("Sentry DSN is empty, skipping initialization")
            return
        }

        let envName = ConfigManager.shared.currentEnvironment.name
        Log.info("Initializing Sentry for environment: \(envName)")

        SentrySDK.start { options in
            options.dsn = dsn
            options.debug = true
            options.attachScreenshot = true
            options.enableSigtermReporting = true
            options.attachStacktrace = true
            options.attachViewHierarchy = true
            options.sendDefaultPii = true

            options.environment = "\(envName)-debug"
        }

        Log.info("Sentry initialized successfully")
    }

    private static func shouldEnableSentry() -> Bool {
        let environment = ConfigManager.shared.currentEnvironment

        switch environment {
        case .local, .dev:
            #if DEBUG
            return false
            #else
            return true
            #endif
        case .production, .tests:
            return false
        }
    }
}

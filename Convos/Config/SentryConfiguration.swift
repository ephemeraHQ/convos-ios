import ConvosCore
import Foundation
import Sentry

enum SentryConfiguration {
    static func configure() {
        guard shouldEnableSentry() else {
            Logger.info("Sentry disabled: not a Convos (Dev) distribution build")
            return
        }

        let dsn = Secrets.SENTRY_DSN
        guard !dsn.isEmpty else {
            Logger.error("Sentry DSN is empty, skipping initialization")
            return
        }

        Logger.info("Initializing Sentry for Convos (Dev) distribution build")

        SentrySDK.start { options in
            options.dsn = dsn
            options.debug = true
            options.attachScreenshot = true
            options.enableSigtermReporting = true
            options.attachStacktrace = true
            options.attachViewHierarchy = true
            options.sendDefaultPii = true

            options.environment = "dev-distribution"
        }

        Logger.info("Sentry initialized successfully")
    }

    private static func shouldEnableSentry() -> Bool {
        let environment = ConfigManager.shared.currentEnvironment

        guard case .dev = environment else {
            return false
        }

        #if DEBUG
        return false
        #else
        return true
        #endif
    }
}

import Foundation
import Sentry

enum SDKConfiguration {
    static func configureSDKs() {
        configureSentrySDK()
    }

    private static func configureSentrySDK() {
        SentrySDK.start { options in
            options.dsn = Secrets.SENTRY_DSN
            options.debug = true // Enabling debug when first installing is always helpful
            options.diagnosticLevel = .warning
            options.attachScreenshot = true
            options.enableSigtermReporting = true
            options.attachStacktrace = true
            options.attachViewHierarchy = true

            // Adds IP for users.
            // For more information, visit: https://docs.sentry.io/platforms/apple/data-management/data-collected/
            options.sendDefaultPii = true
        }
    }
}

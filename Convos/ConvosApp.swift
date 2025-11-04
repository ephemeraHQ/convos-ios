import ConvosCore
import SwiftUI
import UserNotifications

@main
struct ConvosApp: App {
    @UIApplicationDelegateAdaptor(ConvosAppDelegate.self) private var appDelegate: ConvosAppDelegate

    let session: any SessionManagerProtocol
    let conversationsViewModel: ConversationsViewModel

    init() {
        let environment = ConfigManager.shared.currentEnvironment
        Logger.configure(environment: environment)

        switch environment {
        case .production:
            Logger.Default.configureForProduction(true)
        default:
            Logger.Default.configureForProduction(false)
        }

        Logger.info("App starting with environment: \(environment)")

        // Run migration to wipe app data (must be done synchronously before app starts)
        Self.runDataWipeMigrationSync(environment: environment)

        // Configure Firebase BEFORE creating ConvosClient
        // This prevents a race condition where SessionManager tries to use AppCheck before it's configured
        switch environment {
        case .tests:
            Logger.info("Running in test environment, skipping Firebase config...")
        default:
            if let url = ConfigManager.shared.currentEnvironment.firebaseConfigURL {
                FirebaseHelperCore.configure(with: url)
            } else {
                Logger.error("Missing Firebase plist URL for current environment")
            }
        }

        let convos: ConvosClient = .client(environment: environment)
        self.session = convos.session
        self.conversationsViewModel = .init(session: session)
        appDelegate.session = session
    }

    var body: some Scene {
        WindowGroup {
            ConversationsView(viewModel: conversationsViewModel)
                .withSafeAreaEnvironment()
        }
    }

    // MARK: - Migration

    private static func runDataWipeMigrationSync(environment: AppEnvironment) {
        let migrationKey = "data_wipe_migration_v1_completed"
        let defaults = UserDefaults.standard

        // Check if migration has already been run
        guard !defaults.bool(forKey: migrationKey) else {
            Logger.info("Data wipe migration already completed, skipping")
            return
        }

        Logger.info("Running data wipe migration...")

        // 1. Wipe documents directory
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        if let documentsDirectory = documentsDirectory {
            do {
                let fileURLs = try FileManager.default.contentsOfDirectory(
                    at: documentsDirectory,
                    includingPropertiesForKeys: nil
                )
                for fileURL in fileURLs {
                    try FileManager.default.removeItem(at: fileURL)
                    Logger.info("Deleted: \(fileURL.lastPathComponent)")
                }
                Logger.info("Successfully wiped documents directory")
            } catch {
                Logger.error("Error wiping documents directory: \(error)")
            }
        }

        // 2. Wipe convos.sqlite and related files from defaultDatabasesDirectoryURL
        let databasesDirectory = environment.defaultDatabasesDirectoryURL
        let databaseFiles = [
            "convos.sqlite",
            "convos.sqlite-wal",
            "convos.sqlite-shm"
        ]

        for fileName in databaseFiles {
            let fileURL = databasesDirectory.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                do {
                    try FileManager.default.removeItem(at: fileURL)
                    Logger.info("Deleted database file: \(fileName)")
                } catch {
                    Logger.error("Error deleting \(fileName): \(error)")
                }
            }
        }

        // 3. Mark migration as completed
        defaults.set(true, forKey: migrationKey)
        defaults.synchronize()
        Logger.info("Data wipe migration completed and marked as done")
    }
}

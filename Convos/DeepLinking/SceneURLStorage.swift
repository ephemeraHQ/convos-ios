import ConvosCore
import Foundation
import Observation

/// Shared storage for coordinating URL handling between SceneDelegate and SwiftUI App
@MainActor
@Observable
class SceneURLStorage {
    static let shared: SceneURLStorage = SceneURLStorage()

    private(set) var pendingURL: URL?

    private init() {}

    func storePendingURL(_ url: URL) {
        Logger.info("Storing pending URL for SwiftUI processing")
        pendingURL = url
    }

    func consumePendingURL() -> URL? {
        Logger.info("Consuming pending URL")
        defer { pendingURL = nil }
        return pendingURL
    }

    func hasPendingURL() -> Bool {
        return pendingURL != nil
    }
}

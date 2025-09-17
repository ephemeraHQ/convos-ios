import ConvosCore
import Foundation

/// Shared storage for coordinating URL handling between SceneDelegate and SwiftUI App
@MainActor
class SceneURLStorage: ObservableObject {
    static let shared: SceneURLStorage = SceneURLStorage()

    @Published private(set) var pendingURL: URL?

    private init() {}

    func storePendingURL(_ url: URL) {
        Logger.info("Storing pending URL for SwiftUI processing")
        pendingURL = url
    }

    func consumePendingURL() -> URL? {
        defer { pendingURL = nil }
        return pendingURL
    }

    func hasPendingURL() -> Bool {
        return pendingURL != nil
    }
}

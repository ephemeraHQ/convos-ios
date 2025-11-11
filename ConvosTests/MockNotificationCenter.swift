import UserNotifications
@testable import Convos

/// Mock notification center for testing
@MainActor
final class MockNotificationCenter: NotificationCenterProtocol, @unchecked Sendable {
    var authStatus: UNAuthorizationStatus = .notDetermined
    var shouldGrantPermission = false
    var deniedStatus: UNAuthorizationStatus = .denied

    nonisolated func authorizationStatus() async -> UNAuthorizationStatus {
        await MainActor.run { authStatus }
    }
}

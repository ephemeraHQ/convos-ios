import ConvosCore
import UserNotifications

class NotificationService: UNNotificationServiceExtension {
    private var pushHandler: CachedPushNotificationHandler?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        pushHandler = NotificationExtensionEnvironment.createPushNotificationHandler()
        pushHandler?.handlePushNotification(userInfo: request.content.userInfo)
        contentHandler(request.content)
    }

    override func serviceExtensionTimeWillExpire() {
        pushHandler?.cleanup()
    }
}

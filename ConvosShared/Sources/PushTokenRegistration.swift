import Foundation

// MARK: - Push Token Registration Models

public struct PushTokenRegistrationRequest: Codable {
    public let deviceId: String
    public let pushToken: String
    public let pushTokenType: PushTokenType
    public let apnsEnvironment: ApnsEnvironment
    public let installations: [InstallationInfo]

    public init(
        deviceId: String,
        pushToken: String,
        pushTokenType: PushTokenType = .apns,
        apnsEnvironment: ApnsEnvironment,
        installations: [InstallationInfo]
    ) {
        self.deviceId = deviceId
        self.pushToken = pushToken
        self.pushTokenType = pushTokenType
        self.apnsEnvironment = apnsEnvironment
        self.installations = installations
    }
}

public struct InstallationInfo: Codable {
    public let identityId: String
    public let xmtpInstallationId: String

    public init(identityId: String, xmtpInstallationId: String) {
        self.identityId = identityId
        self.xmtpInstallationId = xmtpInstallationId
    }
}

public enum PushTokenType: String, Codable {
    case apns
    case expo
    case fcm
}

public enum ApnsEnvironment: String, Codable {
    case sandbox
    case production
}

public struct PushTokenRegistrationResponse: Codable {
    public let responses: [InstallationRegistrationResponse]

    public init(responses: [InstallationRegistrationResponse]) {
        self.responses = responses
    }
}

public struct InstallationRegistrationResponse: Codable {
    public let status: String
    public let xmtpInstallationId: String
    public let validUntil: Int64?

    public init(status: String, xmtpInstallationId: String, validUntil: Int64? = nil) {
        self.status = status
        self.xmtpInstallationId = xmtpInstallationId
        self.validUntil = validUntil
    }
}

// MARK: - Device Registration Models

public struct DeviceRegistrationRequest: Codable {
    public let deviceId: String
    public let platform: String
    public let appVersion: String
    public let osVersion: String

    public init(deviceId: String, platform: String = "ios", appVersion: String, osVersion: String) {
        self.deviceId = deviceId
        self.platform = platform
        self.appVersion = appVersion
        self.osVersion = osVersion
    }
}

public struct DeviceRegistrationResponse: Codable {
    public let deviceId: String
    public let status: String

    public init(deviceId: String, status: String) {
        self.deviceId = deviceId
        self.status = status
    }
}

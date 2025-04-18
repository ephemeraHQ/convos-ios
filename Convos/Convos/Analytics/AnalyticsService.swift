//
//  AnalyticsService.swift
//  Convos
//
//  Created by Jarod Luebbert on 4/18/25.
//

import Foundation
import PostHog

protocol AnalyticsServiceProtocol {
    
    static var shared: AnalyticsServiceProtocol { get }
    
    func config()
    func track(event: String, properties: [String: Any]?)
    func identify(userId: String, properties: [String: Any]?)
    func reset()
    func screen(name: String, properties: [String: Any]?)
}

final class PosthogAnalyticsService: AnalyticsServiceProtocol {
    
    static var shared: AnalyticsServiceProtocol = PosthogAnalyticsService()
    
    func config() {
        let config = PostHogConfig(apiKey: Secrets.POSTHOG_API_KEY,
                                   host: Secrets.POSTHOG_HOST)
        PostHogSDK.shared.setup(config)
    }
    
    func track(event: String, properties: [String: Any]?) {
        PostHogSDK.shared.capture(event, properties: properties)
    }
    
    func identify(userId: String, properties: [String: Any]?) {
    }
    
    func reset() {
        PostHogSDK.shared.reset()
    }
    
    func screen(name: String, properties: [String: Any]?) {
        PostHogSDK.shared.screen(name, properties: properties)
    }
}

final class MockAnalyticsService: AnalyticsServiceProtocol {
    static var shared: AnalyticsServiceProtocol = MockAnalyticsService()
    func config() {}
    func track(event: String, properties: [String: Any]?) {}
    func identify(userId: String, properties: [String: Any]?) {}
    func reset() {}
    func screen(name: String, properties: [String: Any]?) {}
}
